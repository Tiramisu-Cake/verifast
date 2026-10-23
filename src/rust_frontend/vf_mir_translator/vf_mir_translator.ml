module AstAux = Ast_aux
module D = Vf_mir_decoder

module RustBelt = Rustbelt
module LocAux = Src_loc_aux

module DecoderAux = Decoder_aux

(* R23's narrow array interpretation is enabled only while translating the
   exact opted-in source body. The resulting type closures capture this
   selection; unmarked bodies retain the historical unsupported array path. *)
let r23_source_array3_interp_active = ref false

module IntAux = struct
  module Make (StdintMod : sig
    type t

    val zero : t
    val max_int : t
    val min_int : t
    val ( - ) : t -> t -> t
    val ( + ) : t -> t -> t
    val div : t -> t -> t
    val rem : t -> t -> t
    val to_int : t -> int
    val of_int : int -> t
    val to_string : t -> string
  end) =
  struct
    open StdintMod

    let try_add (a : t) (b : t) =
      if a >= zero then
        if b <= max_int - a then Ok (a + b) else Error (`IntAuxAdd "Overflow")
      else if b >= min_int - a then Ok (a + b)
      else Error (`IntAuxAdd "Underflow")

    let try_to_int (a : t) =
      let i = to_int a in
      if a = of_int i then Ok i else Error `IntAuxToInt

    let rec to_big_int (a : t) = Big_int.big_int_of_string (to_string a)
  end

  module Int8 = Make (Stdint.Int8)
  module Int16 = Make (Stdint.Int16)
  module Int32 = Make (Stdint.Int32)
  module Int64 = Make (Stdint.Int64)
  module Int128 = Make (Stdint.Int128)
  module Uint8 = Make (Stdint.Uint8)
  module Uint16 = Make (Stdint.Uint16)
  module Uint32 = Make (Stdint.Uint32)
  module Uint64 = Make (Stdint.Uint64)
  module Uint128 = Make (Stdint.Uint128)
end

module SizeAux : sig
  (* These types have the invariant of holding a meaningful number of bits, bytes, etc. *)
  type sz_bits
  type sz_bytes

  val sz_bits_of_int :
    int -> (sz_bits, [> `SizeAuxSzBitsOfInt of string ]) result

  val sz_bytes_of_int :
    int -> (sz_bytes, [> `SizeAuxSzBytesOfInt of string ]) result

  val sz_bytes_of_sz_bits : sz_bits -> sz_bytes
  val int_of_sz_bytes : sz_bytes -> int
end = struct
  type sz_bits = int
  type sz_bytes = int

  let sz_bits_of_int bits =
    if bits = 0 then Ok bits
    else
      let n = Float.log2 @@ float_of_int @@ bits in
      let n_is_int_and_bits_gt_zero =
        FP_zero == Float.classify_float @@ fst @@ Float.modf @@ n
      in
      if not (n_is_int_and_bits_gt_zero && int_of_float n >= 3) then
        Error
          (`SizeAuxSzBitsOfInt
            "The number of bits should be 0 or 2^n such that n is an integer \
             and n>=3")
      else Ok bits

  let sz_bytes_of_int bytes =
    if bytes < 0 then
      Error
        (`SizeAuxSzBytesOfInt
          "The number of bytes should be a non-negative integer")
    else Ok bytes

  let sz_bytes_of_sz_bits n = n / 8
  let int_of_sz_bytes sb = sb
end

module Hir = struct
  type generic_param = GenParamLifetime | GenParamType | GenParamConst
end

module Mir = struct
  type mutability = Mut | Not

  type generic_arg =
    | GenArgLifetime of string
    | GenArgType of ty_info
    | GenArgConst of Ast.type_expr

  and ty_info = { vf_ty : Ast.type_expr; interp : RustBelt.ty_interp }

  type annot = { span : Ast.loc; raw : string }

  type local_decl = {
    mutability : mutability;
    id : string;
    ty : ty_info Lazy.t;
    loc : Ast.loc;
  }

  type source_info = { span : Ast.loc; scope : unit }

  type terminator =
    | GotoTerminator of Ast.loc * string
    | EncodedTerminator (* The terminator is encoded into the statements *)

  type bb_walk_state = NotSeen | Walking of int * basic_block list | Exhausted

  and basic_block = {
    id : string;
    mutable statements : Ast.stmt list;
    mutable terminator_stmts : Ast.stmt list;
    mutable terminator : terminator;
    mutable successors : string list;
    mutable external_predecessor_count : int;
        (* Number of non-descendant predecessors (i.e. that jump to the start of the loop) *)
    mutable internal_predecessor_count : int;
        (* Number of descendant predecessors (i.e. that jump to the end of the loop body) *)
    mutable walk_state : bb_walk_state;
    mutable is_block_head : bool;
    mutable parent : basic_block option;
        (* If this BB is inside a block (i.e. not the head), points to the innermost containing block's block head *)
    mutable children : basic_block list;
  }

  type fn_call_dst_data = {
    dst : Ast.expr * bool (* place is mutable *);
    dst_bblock_id : string;
  }

  type int_ty = ISize | I8 | I16 | I32 | I64 | I128

  let int_ty_to_string (it : int_ty) =
    match it with
    | ISize -> "isize"
    | I8 -> "i8"
    | I16 -> "i16"
    | I32 -> "i32"
    | I64 -> "i64"
    | I128 -> "i128"

  let int_ty_bits_len (it : int_ty) =
    match it with
    | ISize ->
        Error
          (`UIntTyBitsLen
            "The number of bits of a isize value is not specified by Rust")
    | I8 -> Ok 8
    | I16 -> Ok 16
    | I32 -> Ok 32
    | I64 -> Ok 64
    | I128 -> Ok 128

  type u_int_ty = USize | U8 | U16 | U32 | U64 | U128

  let u_int_ty_to_string (uit : u_int_ty) =
    match uit with
    | USize -> "usize"
    | U8 -> "u8"
    | U16 -> "u16"
    | U32 -> "u32"
    | U64 -> "u64"
    | U128 -> "u128"

  let u_int_ty_bits_len (uit : u_int_ty) =
    match uit with
    | USize ->
        Error
          (`UIntTyBitsLen
            "The number of bits of a usize value is not specified by Rust")
    | U8 -> Ok 8
    | U16 -> Ok 16
    | U32 -> Ok 32
    | U64 -> Ok 64
    | U128 -> Ok 128

  type var_debug_info_internal = VdiiPlace of { id : string } | VdiiConstant

  type var_debug_info = {
    internal : var_debug_info_internal;
    surf_name : string;
  }

  type debug_info = { id : Ast.loc; info : var_debug_info list }
  type visibility = Public | Restricted
  type adt_kind = Struct | Enum | Union

  let decl_mir_adt_kind (d : Ast.decl) =
    match d with
    | Ast.Struct _ -> Ok Struct
    | Ast.Inductive _ -> Ok Enum
    | Ast.Union _ -> failwith "Todo: Unsupported ADT"
    | _ -> failwith "decl_mir_adt_kind: Not an ADT"

  type aggregate_kind =
    | AggKindArray of ty_info
    | AggKindAdt of {
        adt_kind : adt_kind;
        adt_name : string;
        variant_name : string;
        fields : D.aggregate_kind_adt_data_field_info list;
      }
    | AggKindTuple
    | AggKindClosure

  type field_def_tr = {
    name : string;
    ty : ty_info;
    vis : visibility;
    loc : Ast.loc;
  }

  type variant_def_tr = {
    loc : Ast.loc;
    name : string;
    fields : field_def_tr list;
  }

  type adt_def_tr = {
    loc : Ast.loc;
    name : string;
    tparams : string list;
    lft_params : string list;
    (* The fields of the Rust struct, minus those fields F such that that sizeof(F) = 0 && F.ty.OWN = True *)
    fds_no_zst : field_def_tr list;
    def : Ast.decl;
    aux_decls : Ast.decl list;
    full_bor_content : Ast.decl option;
    proof_obligs : Ast.decl list;
    delayed_proof_obligs : (adt_def_tr list -> Ast.decl) list;
  }
end

module TrTyTuple = struct
  let tuple0_name = "std_tuple_0_"
  let make_tuple_type_name arity = Printf.sprintf "std_tuple_%d_" arity
end

module TrTyInt = struct
  let calc_rank (bytes : SizeAux.sz_bytes) =
    let open SizeAux in
    int_of_float @@ Float.log2 @@ float_of_int @@ int_of_sz_bytes @@ bytes
end

module TrTyRawPtr = struct
  type ty_raw_ptr_info = {
    mutability : Mir.mutability;
    pointee_ty_info : Mir.ty_info;
  }
end

module TrName = struct
  let tag_internal (n : string) = "$" ^ n

  let translate_def_path (dp : string) =
    (*
    let open Str in
    let r = regexp {|::|} in
    global_replace r "_" dp
    *)
    dp

  let make_tmp_var_name base_name = tag_internal "temp_var_" ^ base_name

  let lft_name_without_apostrophe n =
    if String.starts_with ~prefix:"'" n then String.sub n 1 (String.length n - 1)
    else
      failwith
        ("Encountered a lifetime name that does not start with an apostrophe: "
       ^ n)

  let is_from_std_lib path = String.starts_with ~prefix:"std::" path

  let split_def_path mod_path def_path =
    let open String in
    let rel_def_path =
      (* e.g. mod_path = "ptr" && def_path = "ptr::NonNull::<T>::as_ptr" *)
      if starts_with ~prefix:(mod_path ^ "::") def_path then
        sub def_path
          (length mod_path + 2)
          (length def_path - length mod_path - 2)
      else
        (*
        - Empty module path => crate root
          - e.g. mod_path = "" && def_path = "foo"
          - e.g. mod_path = "" && def_path = "<impl std::clone::Clone for ptr::NonNull<T>>::clone"
        - The module path does not apear at the start of the path for trait implementations inside the module:
          - e.g. mod_path = "ptr" && def_path = "<ptr::NonNull<T> as std::clone::Clone>::clone"
        *)
        def_path
    in
    (mod_path, rel_def_path)
end

let split_item_name n =
  match String.rindex_opt n ':' with
  | None -> ("", n)
  | Some i ->
      let pac = String.sub n 0 (i - 1) in
      let item = String.sub n (i + 1) (String.length n - i - 1) in
      (pac, item)

let qualified_derived_name format name =
  let package, name = split_item_name name in
  if package = "" then Printf.sprintf format name
  else package ^ "::" ^ Printf.sprintf format name

let padding_pred_name sn = qualified_derived_name "struct_%s_padding" sn

module type VF_MIR_TRANSLATOR_ARGS = sig
  val data_model_opt : Ast.data_model option
  val report_should_fail : string -> Ast.loc0 -> unit
  val report_range : Lexer.range_kind -> Ast.loc0 -> unit
  val report_macro_call : Ast.loc0 -> Ast.loc0 -> unit
  val verbose_flags : string list
  val skip_specless_fns : bool
  val allow_ignore_ref_creation : bool
  val ignore_ref_creation : bool
  val ignore_unwind_paths : bool
  val rocq_writer : Rocq_writer.rocq_writer
end

module Make (Args : VF_MIR_TRANSLATOR_ARGS) = struct
  open Ocaml_aux
  module VfMirAnnotParser = Vf_mir_annot_parser.Make (Args)
  module VfMirCapnpAlias = Vf_mir_capnp_alias
  module VfMirRd = VfMirCapnpAlias.VfMirRd
  open VfMirCapnpAlias

  module CapnpAux = struct
    open Stdint

    let int128_get (i_cpn : Int128Rd.t) : Int128.t =
      let open Int128Rd in
      let open Int128 in
      let h = h_get i_cpn in
      let l = l_get i_cpn in
      let r = of_int64 h in
      let r = shift_left r 64 in
      let r = add r (of_uint64 l) in
      r

    let uint128_get (ui_cpn : UInt128Rd.t) : Uint128.t =
      let open UInt128Rd in
      let open Uint128 in
      let h = h_get ui_cpn in
      let l = l_get ui_cpn in
      let r = of_uint64 h in
      let r = shift_left r 64 in
      let r = add r (of_uint64 l) in
      r

    let rec ind_list_get_list (il_cpn : IndListRd.t) =
      let open IndListRd in
      match get il_cpn with
      | Nil -> Ok []
      | Cons cons_cpn ->
          let open Cons in
          let h_cpn = VfMirRd.of_pointer (h_get cons_cpn) in
          let t_cpn = t_get cons_cpn in
          let* t_cpn = ind_list_get_list t_cpn in
          Ok (h_cpn :: t_cpn)
      | Undefined _ ->
          Error (`CapnpIndListGetList "Unknown inductive list constructor")
  end

  let prelude_path =
    Filename.concat (Filename.dirname Sys.executable_name) "rust/prelude.rsspec"

  let parse_prelude () =
    let prelude_name = Filename.basename prelude_path in
    let decls =
      let ds = VfMirAnnotParser.parse_rsspec_file prelude_path in
      let pos = (prelude_path, 1, 1) in
      let loc = Ast.Lexed (pos, pos) in
      [ Ast.PackageDecl (loc, "", [], ds) ]
    in
    let header =
      ( Ast.dummy_loc,
        (Lexer.AngleBracketInclude, prelude_name, prelude_path),
        [],
        decls )
    in
    [ header ]

  let parse_header (crateName : string) (header_path : string) =
    let header_name = Filename.basename header_path in
    let decls =
      if not (Filename.check_suffix header_name ".rsspec") then
        failwith
          (Printf.sprintf "Bad header name '%s': should end with .rsspec"
             header_name);
      let ds = VfMirAnnotParser.parse_rsspec_file header_path in
      let pos = (header_path, 1, 1) in
      let loc = Ast.Lexed (pos, pos) in
      Rust_parser.flatten_module_decls loc []
        [ Ast.ModuleDecl (loc, crateName, [], ds) ]
    in
    let header =
      ( Ast.dummy_loc,
        (Lexer.AngleBracketInclude, header_name, header_path),
        [ prelude_path ],
        decls )
    in
    [ header ]

  module VF0 = Verifast0

  let translate_real_file_name (real_fname : D.real_file_name) =
    match real_fname with
    | LocalPath path -> Ok path
    | Remapped {local_path=local_path_opt_cpn; virtual_name} ->
        match local_path_opt_cpn with
        | Nothing -> Ok ("/RUSTC_VIRTUAL_PATH" ^ virtual_name)
        | Something {text} ->
            Ok text

  let translate_file_name (fname : D.file_name) =
    match fname with
    | Real real_fname -> translate_real_file_name real_fname
    | QuoteExpansion _ -> failwith "Todo: FileName QuoteExpansion"

  let translate_source_file ({name} : D.source_file) =
    translate_file_name name

  let translate_char_pos ({pos} : D.char_pos) =
    (* Make it 1-based *)
    let cpos = IntAux.Uint64.try_add pos Stdint.Uint64.one in
    cpos

  let translate_loc ({file; line; col} : D.loc) =
    let* file = translate_source_file file in
    let* col = translate_char_pos col in
    let* line = IntAux.Uint64.try_to_int line in
    let* col = IntAux.Uint64.try_to_int col in
    let src_pos = (file, line, col) in
    Ok src_pos

  let translate_decoded_span_data (spanData : D.span_data) =
    match spanData with
      Dummy -> Ok Ast.dummy_loc
    | Regular {lo; hi} ->
      let* lo = translate_loc lo in
      let* hi = translate_loc hi in
      Ok (Ast.Lexed (lo, hi))
  
  let translate_span_data (span_data_cpn: SpanDataRd.t) =
    translate_decoded_span_data (D.decode_span_data span_data_cpn)

  let translate_source_info (src_info_cpn : SourceInfoRd.t) =
    let open SourceInfoRd in
    let span_cpn = span_get src_info_cpn in
    let* span = translate_span_data span_cpn in
    let src_info : Mir.source_info = { span; scope = () } in
    Ok src_info

  let translate_annotation (annot_cpn : AnnotationRd.t) =
    let open AnnotationRd in
    let raw = raw_get annot_cpn in
    let span_cpn = span_get annot_cpn in
    let* span = translate_span_data span_cpn in
    let (Ast.Lexed ((sf_name, sl, sc), (ef_name, el, ec))) = span in
    let* sl = IntAux.Uint64.try_to_int (start_line_get annot_cpn) in
    let* sc = IntAux.Uint64.try_to_int (start_col_get annot_cpn) in
    let* el = IntAux.Uint64.try_to_int (end_line_get annot_cpn) in
    let* ec = IntAux.Uint64.try_to_int (end_col_get annot_cpn) in
    let span = Ast.Lexed ((sf_name, sl, sc), (ef_name, el, ec)) in
    let annot : Mir.annot = { span; raw } in
    Ok annot

  let translate_annot_to_vf_parser_inp ({ span; raw } : Mir.annot) =
    let spos, epos = Ast.lexed_loc span in
    (spos, raw)

  let translate_contract (contract_cpn : ContractRd.t) =
    let open ContractRd in
    let span_cpn = span_get contract_cpn in
    let* loc = translate_span_data span_cpn in
    let* contract_opt =
      let annots_cpn = annotations_get_list contract_cpn in
      if ListAux.is_empty annots_cpn then Ok None
      else
        let* annots = ListAux.try_map translate_annotation annots_cpn in
        let annots = List.map translate_annot_to_vf_parser_inp annots in
        Ok (Some (VfMirAnnotParser.parse_func_contract loc annots))
    in
    Ok (loc, contract_opt)

  let translate_ghost_stmt (gs_cpn : AnnotationRd.t) =
    let open AnnotationRd in
    let* gs = translate_annotation gs_cpn in
    let gs = translate_annot_to_vf_parser_inp gs in
    Ok (VfMirAnnotParser.parse_ghost_stmt gs)

  let translate_ghost_decl_batch (gh_decl_batch_cpn : AnnotationRd.t) =
    let* gh_decl_b = translate_annotation gh_decl_batch_cpn in
    let gh_decl_b = translate_annot_to_vf_parser_inp gh_decl_b in
    Ok (VfMirAnnotParser.parse_ghost_use_decl_or_decl_batch gh_decl_b)

  let translate_ghost_decl_block (gdb_cpn : BodyRd.GhostDeclBlock.t) =
    let open BodyRd.GhostDeclBlock in
    let open AnnotationRd in
    let* gh_decl_b = translate_annotation (start_get gdb_cpn) in
    let gh_decl_b_parser_input = translate_annot_to_vf_parser_inp gh_decl_b in
    let ghost_decls =
      VfMirAnnotParser.parse_ghost_decl_batch gh_decl_b_parser_input
    in
    let ghost_decls =
      if Args.ignore_unwind_paths then
        List.map Rust_parser.result_decl_of_outcome_decl ghost_decls
      else ghost_decls
    in
    let* closeBraceSpan = translate_span_data (close_brace_span_get gdb_cpn) in
    let ghost_decl_block =
      Ast.BlockStmt (gh_decl_b.span, ghost_decls, [], closeBraceSpan, ref [])
    in
    Ok ghost_decl_block

  let translate_loop_spec_block (lsb_cpn : BodyRd.LoopSpecBlock.t) =
    let open BodyRd.LoopSpecBlock in
    let open AnnotationRd in
    let* loop_spec_annot = translate_annotation (start_get lsb_cpn) in
    let loop_spec_parser_input = translate_annot_to_vf_parser_inp loop_spec_annot in
    let loop_spec =
      VfMirAnnotParser.parse_ghost_stmt loop_spec_parser_input
    in
    let* closeBraceSpan = translate_span_data (close_brace_span_get lsb_cpn) in
    let loop_spec_block =
      Ast.BlockStmt (loop_spec_annot.span, [], [loop_spec], closeBraceSpan, ref [])
    in
    Ok loop_spec_block

  let translate_mutability (mutability_cpn : MutabilityRd.t) =
    match MutabilityRd.get mutability_cpn with
    | Mut -> Ok Mir.Mut
    | Not -> Ok Mir.Not
    | Undefined _ ->
        Error (`TrMutability "Unknown Mir mutability discriminator")

  let translate_symbol (sym_cpn : SymbolRd.t) = SymbolRd.name_get sym_cpn

  let translate_ident (i_cpn : IdentRd.t) =
    let open IdentRd in
    let name_cpn = name_get i_cpn in
    let name = translate_symbol name_cpn in
    let span_cpn = span_get i_cpn in
    let* loc = translate_span_data span_cpn in
    Ok (name, loc)

  let translate_region (reg_cpn : RegionRd.t) = RegionRd.id_get reg_cpn

  let vf_ty_arg_of_region loc (reg : string) =
    match reg with
    | "'static" -> Ast.ManifestTypeExpr (loc, StaticLifetime)
    | "'<erased>" -> Ast.InferredTypeExpr loc
    | x -> Ast.IdentTypeExpr (loc, None, x)

  let translate_region_expr loc (reg_cpn : D.region) =
    vf_ty_arg_of_region loc reg_cpn.id

  let int_size_rank = Ast.PtrRank

  let simple_shr loc fbc_name lft tid l =
    Ok
      (Ast.CoefAsn
         ( loc,
           DummyPat,
           CallExpr
             ( loc,
               "frac_borrow",
               [],
               [],
               [
                 LitPat lft;
                 LitPat
                   (CallExpr
                      (loc, fbc_name, [], [], [ LitPat tid; LitPat l ], Static));
               ],
               Static ) ))

  let simple_shr_pred loc fbc_name =
    Ok
      (Ast.CallExpr
         (loc, "simple_share", [], [], [ LitPat (Var (loc, fbc_name)) ], Static))

  let translate_int_ty (int_ty_cpn : D.int_ty) (loc : Ast.loc) =
    let open Ast in
    let sz_rank_name i =
      let open SizeAux in
      let* bits = Mir.int_ty_bits_len i in
      let* sz_bits = sz_bits_of_int bits in
      let sz_bytes = sz_bytes_of_sz_bits sz_bits in
      let sz_expr =
        IntLit
          ( loc,
            Big_int.big_int_of_int @@ int_of_sz_bytes @@ sz_bytes,
            (*decimal*) true,
            (*U suffix*) true,
            NoLSuffix )
      in
      let rank = FixedWidthRank (TrTyInt.calc_rank sz_bytes) in
      Ok (sz_expr, rank, Mir.int_ty_to_string i)
    in
    let* sz_expr, rank, ty_name =
      match int_ty_cpn with
      | ISize ->
          (* isize is pointer-sized *)
          let ptr_sz_expr =
            SizeofExpr (loc, TypeExpr (ManifestTypeExpr (loc, PtrType Void)))
          in
          Ok (ptr_sz_expr, int_size_rank, Mir.int_ty_to_string Mir.ISize)
      | I8 -> sz_rank_name Mir.I8
      | I16 -> sz_rank_name Mir.I16
      | I32 -> sz_rank_name Mir.I32
      | I64 -> sz_rank_name Mir.I64
      | I128 -> sz_rank_name Mir.I128
    in
    let own tid vs = Ok (True loc) in
    let fbc_name = ty_name ^ "_full_borrow_content" in
    let full_bor_content = RustBelt.simple_fbc loc fbc_name in
    let points_to tid l vid_op =
      (* Todo: The size and bounds of the integer that this assertion is specifying will depend on the pointer `l` type
         which is error-prone. It is helpful if we add a sanity-check or use elevated `integer_(...)` predicates with bound infos *)
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    let ty_info =
      {
        Mir.vf_ty = ManifestTypeExpr (loc, Int (Signed, rank));
        interp =
          RustBelt.
            {
              size = sz_expr;
              own;
              shr = simple_shr loc fbc_name;
              full_bor_content;
              points_to;
              pointee_fbc = None;
            };
      }
    in
    Ok ty_info

  let translate_u_int_ty (u_int_ty_cpn : D.uint_ty) (loc : Ast.loc) =
    let open Ast in
    let sz_rank_name ui =
      let open SizeAux in
      let* bits = Mir.u_int_ty_bits_len ui in
      let* sz_bits = sz_bits_of_int bits in
      let sz_bytes = sz_bytes_of_sz_bits sz_bits in
      let sz_expr =
        IntLit
          ( loc,
            Big_int.big_int_of_int @@ int_of_sz_bytes @@ sz_bytes,
            (*decimal*) true,
            (*U suffix*) true,
            NoLSuffix )
      in
      let rank = FixedWidthRank (TrTyInt.calc_rank sz_bytes) in
      Ok (sz_expr, rank, Mir.u_int_ty_to_string ui)
    in
    let* sz_expr, rank, ty_name =
      match u_int_ty_cpn with
      | USize ->
          (* usize is pointer-sized *)
          let ptr_sz_expr =
            SizeofExpr (loc, TypeExpr (ManifestTypeExpr (loc, PtrType Void)))
          in
          Ok (ptr_sz_expr, int_size_rank, Mir.u_int_ty_to_string Mir.USize)
      | U8 -> sz_rank_name Mir.U8
      | U16 -> sz_rank_name Mir.U16
      | U32 -> sz_rank_name Mir.U32
      | U64 -> sz_rank_name Mir.U64
      | U128 -> sz_rank_name Mir.U128
    in
    let own tid vs = Ok (True loc) in
    let fbc_name = ty_name ^ "_full_borrow_content" in
    let full_bor_content = RustBelt.simple_fbc loc fbc_name in
    let points_to tid l vid_op =
      (* Todo: The size and bounds of the integer that this assertion is specifying will depend on the pointer `l` type
         which is error-prone. It is helpful if we add a sanity-check or use elevated `integer_(...)` predicates with bound infos *)
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    let ty_info =
      {
        Mir.vf_ty = ManifestTypeExpr (loc, Int (Unsigned, rank));
        interp =
          RustBelt.
            {
              size = sz_expr;
              own;
              shr = simple_shr loc fbc_name;
              full_bor_content;
              points_to;
              pointee_fbc = None;
            };
      }
    in
    Ok ty_info

  let translate_scalar_int (scalar_int_cpn : D.scalar_int) (ty : Ast.type_expr)
      (loc : Ast.loc) =
    let open VfMirRd.ScalarInt in
    let value =
      IntAux.Uint128.to_big_int (DecoderAux.uint128_get scalar_int_cpn.data)
    in
    let mk_const v =
      let open Ast in
      let lit =
        IntLit (loc, v, (*decimal*) true, (*U suffix*) false, LLSuffix)
      in
      Ok (CastExpr (loc, ty, lit))
    in
    let mk_signed_const width =
      let v =
        if Big_int.sign_big_int value >= 0 then value
        else
          Big_int.sub_big_int value
            (Big_int.shift_left_big_int Big_int.unit_big_int (8 * width))
      in
      mk_const v
    in
    match (ty, scalar_int_cpn.size) with
    | ManifestTypeExpr (_, Bool), _ ->
        Ok
          (if Big_int.sign_big_int value <> 0 then Ast.True loc
           else Ast.False loc)
    | ManifestTypeExpr (_, RustChar), 4 ->
        let open Ast in
        Ok
          (CastExpr
             ( loc,
               ManifestTypeExpr (loc, RustChar),
               IntLit (loc, value, true, true, LLSuffix) ))
    | ManifestTypeExpr (_, Ast.Int (Signed, _)), size -> mk_signed_const size
    | ManifestTypeExpr (_, Ast.Int (Unsigned, _)), size -> mk_const value
    | ty, _ ->
      let value = Ast.IntLit (loc, value, (*decimal*) true, (*U suffix*) false, LLSuffix) in
      Ok (Ast.CallExpr (loc, "transmute_uint", [ty], [], [ LitPat value ], Static))

  let substring_eq (s1 : string) (start: int) (s2 : string) =
    let len1 = String.length s1 in
    let len2 = String.length s2 in
    if start < 0 || start + len2 > len1 then false
    else
      let rec iter i =
        i < 0 || (s1.[start + i] = s2.[i] && iter (i - 1))
      in
      iter (len2 - 1)
  
  let rec canonicalize_item_name (name : string) =
    match String.index_opt name '<' with
    | Some i when substring_eq name (i - 2) "::<impl core::" ->
      canonicalize_item_name
        (String.sub name 0 (i - 2)
        ^ "::<impl std::"
        ^ String.sub name (i + 12) (String.length name - i - 12))
    | _ ->
      if String.starts_with ~prefix:"core::" name then
        "std::" ^ String.sub name 6 (String.length name - 6)
      else name

  let translate_adt_def_id (adt_def_id_cpn : D.adt_def_id) =
    canonicalize_item_name @@ adt_def_id_cpn.name

  let rec translate_adt_ty (adt_ty_cpn : D.ty_kind_adt_ty) (loc : Ast.loc) =
    let open AdtTyRd in
    let open Ast in
    let def_path = translate_adt_def_id @@ adt_ty_cpn.id in
    let kind = adt_ty_cpn.kind in
    let substs_cpn = adt_ty_cpn.substs in
    let name = def_path in
    match kind with
    | StructKind | UnionKind -> (
        match def_path, substs_cpn with
        | ("std::cell::UnsafeCell" | "std::mem::ManuallyDrop"), [ arg_cpn ] ->
            let* (Mir.GenArgType arg_ty) = translate_generic_arg arg_cpn loc in
            Ok arg_ty
        | _ ->
            let* gen_args =
              ListAux.try_map
                (fun gen_arg_cpn -> translate_generic_arg gen_arg_cpn loc)
                substs_cpn
            in
            let targs =
              gen_args
              |> Util.flatmap @@ function
                 | Mir.GenArgType arg_ty -> [ arg_ty.vf_ty ]
                 | Mir.GenArgConst ty_expr -> [ ty_expr ]
                 | _ -> []
            in
            let lft_args =
              gen_args
              |> Util.flatmap @@ function
                 | Mir.GenArgLifetime name -> [ vf_ty_arg_of_region loc name ]
                 | _ -> []
            in
            let vf_targs = lft_args @ targs in
            let vf_ty = StructTypeExpr (loc, Some name, None, [], vf_targs) in
            let sz_expr = SizeofExpr (loc, TypeExpr vf_ty) in
            let own tid v =
              let args = List.map (fun x -> LitPat x) [ tid; v ] in
              Ok
                (CallExpr
                   ( loc,
                     name ^ "_own",
                     (*type arguments*) vf_targs,
                     (*indices*) [],
                     args,
                     if vf_targs = [] then PredFamCall else PredCtorCall ))
            in
            let shr lft tid l =
              Ok
                (CoefAsn
                   ( loc,
                     DummyPat,
                     CallExpr
                       ( loc,
                         name ^ "_share",
                         (*type arguments*) vf_targs,
                         (*indices*) [],
                         (*arguments*)
                         List.map (fun e -> LitPat e) [ lft; tid; l ],
                         if vf_targs = [] then PredFamCall else PredCtorCall )
                   ))
            in
            let full_bor_content =
              if lft_args = [] then
                RustBelt.simple_fbc loc (name ^ "_full_borrow_content")
              else fun tid l ->
                Ok
                  (CallExpr
                     ( loc,
                       name ^ "_full_borrow_content",
                       lft_args @ targs,
                       [],
                       List.map (fun e -> LitPat e) [ tid; l ],
                       Static ))
            in
            let points_to tid l vid_op =
              let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
              Ok (PointsTo (loc, l, RegularPointsTo, pat))
            in
            let interp =
              RustBelt.
                {
                  size = sz_expr;
                  own;
                  shr;
                  full_bor_content;
                  points_to;
                  pointee_fbc = None;
                }
            in
            let ty_info = { Mir.vf_ty; interp } in
            Ok ty_info)
    | EnumKind ->
        let* targs =
          ListAux.try_map
            (fun targ_cpn -> translate_generic_arg targ_cpn loc)
            substs_cpn
        in
        let targs =
          targs
          |> List.map @@ function
             | Mir.GenArgLifetime _ ->
                 raise
                   (Ast.StaticError
                      ( loc,
                        "Lifetime arguments are not yet supported here",
                        None ))
             | Mir.GenArgType arg_ty -> arg_ty.vf_ty
             | Mir.GenArgConst ty_expr -> ty_expr
        in
        let vf_ty = ConstructedTypeExpr (loc, name, targs) in
        let sz_expr = SizeofExpr (loc, TypeExpr vf_ty) in
        let own tid v =
          Ok
            (ExprCallExpr
               (loc, TypePredExpr (loc, vf_ty, "own"), [ LitPat tid; LitPat v ]))
        in
        let shr lft tid l =
          Error
            "Expressing shared ownership of an enum value is not yet supported"
        in
        let full_bor_content tid l =
          Error
            "Expressing the full borrow content of an enum value is not yet \
             supported"
        in
        (* Todo: Nested structs *)
        let points_to tid l vid_op =
          let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
          Ok (PointsTo (loc, l, RegularPointsTo, pat))
        in
        let interp =
          RustBelt.
            {
              size = sz_expr;
              own;
              shr;
              full_bor_content;
              points_to;
              pointee_fbc = None;
            }
        in
        let ty_info = { Mir.vf_ty; interp } in
        Ok ty_info

  and translate_tuple_ty (tys_cpn : D.ty list) (loc : Ast.loc) =
    let open Ast in
    let* tys =
      ListAux.try_map (fun ty_cpn -> translate_ty ty_cpn loc) tys_cpn
    in
    let name = TrTyTuple.make_tuple_type_name (List.length tys) in
    let tys = List.map (fun { Mir.vf_ty } -> vf_ty) tys in
    let vf_ty =
      if tys = [] then ManifestTypeExpr (loc, StructType (name, []))
      else StructTypeExpr (loc, Some name, None, [], tys)
    in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own t v =
      if tys = [] then Ok (True loc)
      else
        Ok
          (CallExpr (loc, name ^ "_own", tys, [], [ LitPat t; LitPat v ], Static))
    in
    let fbc_name = name ^ "_full_borrow_content" in
    let full_bor_content = RustBelt.simple_fbc loc fbc_name in
    let shr lft tid l =
      Ok
        (CallExpr
           ( loc,
             name ^ "_share",
             tys,
             [],
             [ LitPat lft; LitPat tid; LitPat l ],
             Static ))
    in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    let ty_info =
      {
        Mir.vf_ty;
        interp =
          RustBelt.
            { size; own; shr; full_bor_content; points_to; pointee_fbc = None };
      }
    in
    Ok ty_info

  and bool_ty_info loc =
    let open Ast in
    let vf_ty = ManifestTypeExpr (loc, Bool) in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own _ _ = Ok (True loc) in
    let fbc_name = "bool_full_borrow_content" in
    let full_bor_content = RustBelt.simple_fbc loc fbc_name in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          {
            size;
            own;
            shr = simple_shr loc fbc_name;
            full_bor_content;
            points_to;
            pointee_fbc = None;
          };
    }

  and char_ty_info loc =
    let open Ast in
    let vf_ty =
      ManifestTypeExpr (loc, RustChar)
      (* https://doc.rust-lang.org/reference/types/textual.html *)
    in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid c =
      Ok
        (CallExpr
           ( loc,
             "char_own",
             (*type arguments*) [],
             (*indices*) [],
             [ LitPat tid; LitPat c ],
             Static ))
      (* Todo: According to https://doc.rust-lang.org/reference/types/textual.html,
         "It is immediate Undefined Behavior to create a char that falls outside this (0 <= v && v <= 0xD7FF || 0xE000 <= v && v <= 0x10FFFF) range".
         So it is not enough to check char ranges in function boundaries. Miri warns about UB when reading an out-of-range character.
         A proposal is to translate char-ptr/ref dereferences to calls to a function with a contract that checks for the range. *)
    in
    let shr = Ok (Var (loc, "char_share")) in
    let fbc_name = "char_full_borrow_content" in
    let full_bor_content = RustBelt.simple_fbc loc fbc_name in
    let points_to tid l vid_op =
      match vid_op with
      | Some vid when vid != "" ->
          let var_pat = VarPat (loc, vid) in
          let var_expr = Var (loc, vid) in
          let* own = own tid var_expr in
          Ok (Sep (loc, PointsTo (loc, l, RegularPointsTo, var_pat), own))
      | _ -> Error "char points_to needs a value id"
    in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          {
            size;
            own;
            shr = simple_shr loc fbc_name;
            full_bor_content;
            points_to;
            pointee_fbc = None;
          };
    }

  and never_ty_info loc =
    let open Ast in
    let vf_ty = ManifestTypeExpr (loc, UnionType "std_empty_") in
    let size =
      IntLit
        ( loc,
          Big_int.zero_big_int,
          (*decimal*) false,
          (*U suffix*) true,
          NoLSuffix )
    in
    let own _ _ = Ok (False loc) in
    let shr lft tid l =
      Error
        "Expressing the shared ownership of the never type is not yet supported"
    in
    let full_bor_content tid l =
      Error
        "Expressing the full borrow content of the never type is not yet \
         supported"
    in
    let points_to _ _ _ = Ok (False loc) in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          { size; own; shr; full_bor_content; points_to; pointee_fbc = None };
    }

  and translate_alias_ty ({kind; def_id; args={kind=Type self_ty}::args}: D.ty_kind_alias_ty) loc =
    let open Ast in
    let* self_ty = translate_ty self_ty loc in
    let* gen_args = ListAux.try_map (fun arg -> translate_generic_arg arg loc) args in
    let targs =
      gen_args
      |> Util.flatmap @@ function
          | Mir.GenArgType arg_ty -> [ arg_ty.vf_ty ]
          | _ -> []
    in
    let lft_args =
      gen_args
      |> Util.flatmap @@ function
          | Mir.GenArgLifetime name -> [ vf_ty_arg_of_region loc name ]
          | _ -> []
    in
    let vf_targs = lft_args @ targs in
    let def_id_separator = String.rindex def_id ':' in
    let trait_name = String.sub def_id 0 (def_id_separator - 1) in
    let trait_name = canonicalize_item_name trait_name in
    let alias_name = String.sub def_id (def_id_separator + 1) (String.length def_id - def_id_separator - 1) in
    let vf_ty = ProjectionTypeExpr (loc, self_ty.vf_ty, trait_name, vf_targs, alias_name) in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid vs =
      Error "Expressing ownership of alias types is not yet supported"
    in
    let shr lft tid l =
      Error "Expressing shared ownership of alias types is not yet supported"
    in
    let full_bor_content tid l =
      Error
        "Expressing the full borrow content of alias types is not yet supported"
    in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    Ok {
      Mir.vf_ty;
      interp =
        RustBelt.
          { size; own; shr; full_bor_content; points_to; pointee_fbc = None };
    }

  and str_ref_ty_info loc lft mut =
    let open Ast in
    let lft_expr = Rust_parser.expr_of_lft_param_expr loc lft in
    let str_ty_expr = ManifestTypeExpr (loc, Str) in
    let vf_ty = RustRefTypeExpr (loc, lft, (match mut with Mir.Not -> Shared | Mir.Mut -> Mutable), str_ty_expr) in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid v =
      match mut with
      | Mir.Not ->
        Ok
          (CoefAsn
             ( loc,
               DummyPat,
               ExprCallExpr
                 ( loc,
                   TypePredExpr (loc, str_ty_expr, "share"),
                   [ LitPat lft_expr; LitPat tid; LitPat v ] ) ))
      | Mir.Mut ->
        (* Same shape as for `&mut T` and `&mut [T]`: a full borrow of the pointee's full borrow content. *)
        Ok
          (CallExpr
             ( loc,
               "full_borrow",
               (*type arguments*) [],
               (*indices*) [],
               (*arguments*)
               [
                 LitPat lft_expr;
                 LitPat
                   (ExprCallExpr
                      ( loc,
                        TypePredExpr (loc, str_ty_expr, "full_borrow_content"),
                        [ LitPat tid; LitPat v ] ));
               ],
               Static ))
    in
    (* For a `&mut str` in-out parameter of a generated contract (see `gen_contract`): the bytes
       and their UTF-8 validity, i.e. the body of `str_full_borrow_content` in
       bin/rust/prelude_core.rsspec. Keep the two in sync. *)
    let pointee_fbc =
      match mut with
      | Mir.Not -> None
      | Mir.Mut ->
        Some (fun tid l suffix ->
          let value_id = Printf.sprintf "_v%s_%s" suffix l in
          let u8_ty_expr = ManifestTypeExpr (loc, Int (Unsigned, FixedWidthRank 0)) in
          Ok
            (Sep
               ( loc,
                 CallExpr
                   ( loc,
                     "array",
                     [ u8_ty_expr ],
                     [],
                     [
                       LitPat (CastExpr (loc, PtrTypeExpr (loc, u8_ty_expr), Var (loc, l)));
                       LitPat (CallExpr (loc, "ptr_len", [], [], [ LitPat (Var (loc, l)) ], Static));
                       VarPat (loc, value_id);
                     ],
                     Static ),
                 Operation
                   ( loc,
                     Eq,
                     [
                       CallExpr (loc, "is_valid_utf8", [], [], [ LitPat (Var (loc, value_id)) ], Static);
                       True loc;
                     ] ) )))
    in
    let ref_ty_name = match mut with Mir.Not -> "&str" | Mir.Mut -> "&mut str" in
    let shr lft tid l =
      Error (Printf.sprintf "Expressing shared ownership of %s values is not yet supported" ref_ty_name)
    in
    let full_bor_content tid l =
      Error
        (Printf.sprintf "Expressing the full borrow content of %s values is not yet supported" ref_ty_name)
    in
    let points_to tid l vid_op =
      Error
        (Printf.sprintf "Expressing a points-to assertion for a %s object is not yet supported" ref_ty_name)
    in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          { size; own; shr; full_bor_content; points_to; pointee_fbc };
    }

  and str_ptr_ty_info loc = (* *const/mut str *)
    let open Ast in
    let vf_ty =
      PtrTypeExpr (loc, ManifestTypeExpr (loc, Str))
    in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid vs =
      Error "Expressing ownership of *const/mut str values is not yet supported"
    in
    let shr lft tid l =
      Error "Expressing shared ownership of *const/mut str values is not yet supported"
    in
    let full_bor_content tid l =
      Error
        "Expressing the full borrow content of *const/mut str values is not yet supported"
    in
    let points_to tid l vid_op =
      Error
        "Expressing a points-to assertion for a *const/mut str object is not yet \
         supported"
    in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          { size; own; shr; full_bor_content; points_to; pointee_fbc = None };
    }

  and slice_ptr_ty_info loc elem_ty_info = (* *const/mut [T] *)
    let open Ast in
    let vf_ty =
      PtrTypeExpr (loc, SliceTypeExpr (loc, elem_ty_info.Mir.vf_ty))
    in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid vs =
      Error "Expressing ownership of *const/mut [_] values is not yet supported"
    in
    let shr lft tid l =
      Error "Expressing shared ownership of *const/mut [_] values is not yet supported"
    in
    let full_bor_content tid l =
      Error
        "Expressing the full borrow content of *const/mut [_] values is not yet supported"
    in
    let points_to tid l vid_op =
      Error
        "Expressing a points-to assertion for a *const/mut [_] object is not yet \
         supported"
    in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          { size; own; shr; full_bor_content; points_to; pointee_fbc = None };
    }

  and slice_ref_ty_info loc lft mut elem_ty_info =
    let open Ast in
    let lft_expr = Rust_parser.expr_of_lft_param_expr loc lft in
    let slice_ty_expr = SliceTypeExpr (loc, elem_ty_info.Mir.vf_ty) in
    let rust_mut = mut in
    let mut = match mut with Mir.Not -> Shared | Mir.Mut -> Mutable in
    let vf_ty =
      RustRefTypeExpr (loc, lft, mut, slice_ty_expr)
    in
    let size = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid v =
      match rust_mut with
      | Mir.Not ->
        Ok
          (CoefAsn
             ( loc,
               DummyPat,
               ExprCallExpr
                 ( loc,
                   TypePredExpr (loc, slice_ty_expr, "share"),
                   [ LitPat lft_expr; LitPat tid; LitPat v ] ) ))
      | Mir.Mut ->
        (* Same shape as for `&mut T`: a full borrow of the pointee's full borrow content. *)
        Ok
          (CallExpr
             ( loc,
               "full_borrow",
               (*type arguments*) [],
               (*indices*) [],
               (*arguments*)
               [
                 LitPat lft_expr;
                 LitPat
                   (ExprCallExpr
                      ( loc,
                        TypePredExpr (loc, slice_ty_expr, "full_borrow_content"),
                        [ LitPat tid; LitPat v ] ));
               ],
               Static ))
    in
    let shr lft tid l =
      Error "Expressing shared ownership of &[_] values is not yet supported"
    in
    let full_bor_content tid l =
      Error
        "Expressing the full borrow content of &[_] values is not yet supported"
    in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    (* For a `&mut [T]` in-out parameter of a generated contract (see `gen_contract`): the elements
       and their ownership, i.e. the body of `slice_full_borrow_content` in
       bin/rust/prelude_core.rsspec, with the same spelling of the element pointer. Keep the two in sync. *)
    let pointee_fbc =
      match rust_mut with
      | Mir.Not -> None
      | Mir.Mut ->
        Some (fun tid l suffix ->
          let value_id = Printf.sprintf "_v%s_%s" suffix l in
          let elem_ty_expr = elem_ty_info.Mir.vf_ty in
          let elems_ptr =
            CastExpr
              ( loc,
                PtrTypeExpr (loc, elem_ty_expr),
                CallExpr
                  ( loc,
                    "strip_pointer_metadata",
                    [],
                    [],
                    [ LitPat (CastExpr (loc, ManifestTypeExpr (loc, InductiveType ("pointer", [])), Var (loc, l))) ],
                    Static ) )
          in
          Ok
            (Sep
               ( loc,
                 CallExpr
                   ( loc,
                     "array",
                     [ elem_ty_expr ],
                     [],
                     [
                       LitPat elems_ptr;
                       LitPat (CallExpr (loc, "ptr_len", [], [], [ LitPat (Var (loc, l)) ], Static));
                       VarPat (loc, value_id);
                     ],
                     Static ),
                 CallExpr
                   ( loc,
                     "foreach",
                     [],
                     [],
                     [
                       LitPat (Var (loc, value_id));
                       LitPat (CallExpr (loc, "own", [ elem_ty_expr ], [], [ LitPat tid ], Static));
                     ],
                     Static ) )))
    in
    {
      Mir.vf_ty;
      interp =
        RustBelt.
          { size; own; shr; full_bor_content; points_to; pointee_fbc };
    }

  and translate_generic_arg (gen_arg_cpn : D.generic_arg) (loc : Ast.loc) =
    let kind_cpn = gen_arg_cpn.kind in
    let open GenArgKindRd in
    match kind_cpn with
    | Lifetime region_cpn ->
        let region = region_cpn.id in
        Ok (Mir.GenArgLifetime region)
    | Type ty_cpn ->
        let* ty_info = translate_ty ty_cpn loc in
        Ok (Mir.GenArgType ty_info)
    | Const ty_const_cpn ->
      let ty_expr =
        match ty_const_cpn.kind with
        (* A const generic parameter used as a const generic argument; it is a
           VeriFast type parameter, just like a type parameter is. *)
        | Param {name} -> Ast.IdentTypeExpr (loc, None, name)
        | Value {ty; val_tree} -> 
          begin match val_tree with
          | Leaf {data; size} ->
              let v = DecoderAux.uint128_get data in
              begin match ty, size with
                {kind=UInt _}, _ ->
                  Ast.LiteralConstTypeExpr (loc, Z.of_uint128 v)
              | {kind=Bool}, 1 ->
                  Ast.LiteralConstTypeExpr (loc, Z.of_uint128 v)
              | {kind=Int _}, _ ->
                  (* Sign-extend the [size]-byte two's-complement value. *)
                  let bits = 8 * size in
                  let i = Stdint.Int128.of_uint128 v in
                  let i =
                    if bits < 128 then
                      Stdint.Int128.shift_right (Stdint.Int128.shift_left i (128 - bits)) (128 - bits)
                    else i
                  in
                  Ast.LiteralConstTypeExpr (loc, Z.of_int128 i)
              | _ -> 
                  failwith "Unsupported constant type or size"
              end
          | _ -> 
              failwith "Unsupported constant value tree"
          end
        | _ -> 
            failwith "Unsupported constant kind"
      in
      Ok (Mir.GenArgConst ty_expr)

  and decode_generic_param (gen_param_cpn : VfMirRd.GenericParamDef.t) =
    let open VfMirRd.GenericParamDef in
    let open VfMirRd.GenericParamDefKind in
    let name = name_get gen_param_cpn in
    match get (kind_get gen_param_cpn) with
    | Type -> `Type name
    | Lifetime -> `Lifetime name
    | Const -> failwith "Const generic parameters are not yet supported"

  and decode_generic_arg (gen_arg_cpn : D.generic_arg) =
    let kind_cpn = gen_arg_cpn.kind in
    match kind_cpn with
    | Lifetime region -> `Lifetime region.id
    | Type ty_cpn -> `Type (decode_ty ty_cpn)
    | Const _ -> `Const

  and string_of_generic_arg arg =
    match arg with
    | `Lifetime r -> r
    | `Type ty -> string_of_decoded_type ty
    | `Const -> "(const)"
    | _ -> "(unknown)"

  and extract_implicit_outlives_clauses_from_generic_arg regions arg =
    match arg with
    | `Lifetime region -> List.map (fun r -> (region, r)) regions
    | `Type ty -> extract_implicit_outlives_clauses regions ty
    | _ -> []

  and translate_fn_name (name : string) (substs_cpn : D.generic_arg list) =
    match (name, substs_cpn) with
    | ( ("std::ops::Deref::deref"|"core::ops::Deref::deref"),
        [
          {
            kind =
              Type { kind = Adt { id = { name = "std::mem::ManuallyDrop"|"core::mem::ManuallyDrop" } } };
          };
        ] ) ->
        "std::mem::ManuallyDrop::deref"
    | ( ("std::ops::DerefMut::deref_mut"|"core::ops::DerefMut::deref_mut"),
        [
          {
            kind =
              Type { kind = Adt { id = { name = "std::mem::ManuallyDrop"|"core::mem::ManuallyDrop" } } };
          };
        ] ) ->
        "std::mem::ManuallyDrop::deref_mut"
    | _ -> name

  and translate_fn_def_ty (fn_def_ty_cpn : D.ty_kind_fn_def_ty) (loc : Ast.loc)
      =
    let id_cpn = fn_def_ty_cpn.id in
    let id = id_cpn.name in
    let name = TrName.translate_def_path id in
    let late_bound_generic_param_count =
      fn_def_ty_cpn.late_bound_generic_param_count
    in
    let substs_cpn = fn_def_ty_cpn.substs in
    let* substs =
      ListAux.try_map
        (fun subst_cpn -> translate_generic_arg subst_cpn loc)
        substs_cpn
    in
    let substs =
      substs
      @ List.init late_bound_generic_param_count (fun i ->
            Mir.GenArgLifetime "'erased")
    in
    let vf_ty =
      Ast.ManifestTypeExpr
        (loc, Ast.FuncType (translate_fn_name name substs_cpn))
    in
    if substs = [] then Ok { Mir.vf_ty; interp = RustBelt.emp_ty_interp loc }
    else Ok { Mir.vf_ty; interp = RustBelt.emp_ty_interp loc }

  and translate_fn_ptr_ty (fn_ptr_ty_cpn : D.ty_kind_fn_ptr_ty) (loc : Ast.loc)
      =
    let output_cpn = fn_ptr_ty_cpn.output in
    let* { Mir.vf_ty = output_ty } = translate_ty output_cpn loc in
    let rt =
      if Args.ignore_unwind_paths then output_ty
      else ConstructedTypeExpr (loc, "fn_outcome", [ output_ty ])
    in
    Ok
      {
        Mir.vf_ty = FuncTypeExpr (loc, rt, []);
        (* Only the return type matters *)
        interp = RustBelt.emp_ty_interp loc;
      }

  and translate_raw_ptr_ty (raw_ptr_ty_cpn : D.ty_kind_raw_ptr_ty)
      (loc : Ast.loc) =
    let open Ast in
    let mut_cpn = raw_ptr_ty_cpn.mutability in
    let mutability = mut_cpn in
    let ty_cpn = raw_ptr_ty_cpn.ty in
    match ty_cpn with
      {kind=Slice elem_ty_cpn} ->
      let* elem_ty_info = translate_ty elem_ty_cpn loc in
      Ok (slice_ptr_ty_info loc elem_ty_info)
    | {kind=Str} ->
      Ok (str_ptr_ty_info loc)
    | _ ->
    let* pointee_ty_info = translate_ty ty_cpn loc in
    let pointee_ty = pointee_ty_info.vf_ty in
    let vf_ty = PtrTypeExpr (loc, pointee_ty) in
    let size_expr = SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid vs = Ok (True loc) in
    let fbc_name = "raw_ptr_full_borrow_content" in
    let full_bor_content = RustBelt.simple_fbc loc fbc_name in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (PointsTo (loc, l, RegularPointsTo, pat))
    in
    let ty_info =
      {
        Mir.vf_ty;
        interp =
          RustBelt.
            {
              size = size_expr;
              own;
              shr = simple_shr loc fbc_name;
              full_bor_content;
              points_to;
              pointee_fbc = None;
            };
      }
    in
    Ok ty_info

  and translate_ref_ty (ref_ty_cpn : D.ty_kind_ref_ty) (loc : Ast.loc) =
    let open Ast in
    let region_cpn = ref_ty_cpn.region in
    let region = translate_region_expr loc region_cpn in
    let lft = Rust_parser.expr_of_lft_param_expr loc region in
    let mut_cpn = ref_ty_cpn.mutability in
    let mut = match mut_cpn with Mut -> Mir.Mut | Not -> Mir.Not in
    let ty_cpn = ref_ty_cpn.ty in
    match ty_cpn.kind with
    | Str -> Ok (str_ref_ty_info loc region mut)
    | Slice elem_ty_cpn ->
        let* elem_ty_info = translate_ty elem_ty_cpn loc in
        Ok (slice_ref_ty_info loc region mut elem_ty_info)
    | _ ->
        let* pointee_ty_info = translate_ty ty_cpn loc in
        let pointee_ty = pointee_ty_info.vf_ty in
        let rust_ref_kind = match mut with Mut -> Mutable | Not -> Shared in
        let vf_ty = RustRefTypeExpr (loc, region, rust_ref_kind, pointee_ty) in
        let sz_expr = SizeofExpr (loc, TypeExpr vf_ty) in
        let RustBelt.
              {
                size = ptee_sz;
                own = ptee_own;
                shr = ptee_shr;
                full_bor_content = ptee_fbc;
                points_to = ptee_points_to;
              } =
          pointee_ty_info.interp
        in
        let* own, shr, full_bor_content, points_to, pointee_fbc =
          match mut with
          | Mir.Mut ->
              let own tid l =
                let* ptee_fbc = ptee_fbc tid l in
                Ok
                  (CallExpr
                     ( loc,
                       "full_borrow",
                       (*type arguments*) [],
                       (*indices*) [],
                       (*arguments*)
                       [ LitPat lft; LitPat ptee_fbc ],
                       Static ))
              in
              let shr lft tid l =
                Error
                  "Calling a function with a mutable reference type as a \
                   generic type argument is not yet supported"
              in
              let full_bor_content tid l =
                (* This will need to add a definition for each mut reference type in the program because the body of the predicate will need to mention
                   [[&mut T]].own which depends on T. Another solution is to make VeriFast support Higher order predicates with non-predicate arguments *)
                Error
                  "Expressing the full borrow content of a mutable reference \
                   type is not yet supported"
                (* CallExpr
                   ( loc,
                     "mut_ref_full_borrow_content",
                     (*type arguments*) [],
                     (*indices*) [],
                     (*arguments*)
                     [ LitPat tid; LitPat l ],
                     Static ) *)
              in
              let points_to tid l vid_op =
                let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
                Ok (PointsTo (loc, l, RegularPointsTo, pat))
              in
              let pointee_fbc tid l suffix =
                let value_id = Printf.sprintf "_v%s_%s" suffix l in
                let* pointee_own = ptee_own tid (Var (loc, value_id)) in
                Ok
                  (Sep
                     ( loc,
                       PointsTo
                         ( loc,
                           Deref (loc, Var (loc, l)),
                           RegularPointsTo,
                           VarPat (loc, value_id) ),
                       pointee_own ))
              in
              Ok (own, shr, full_bor_content, points_to, Some pointee_fbc)
          | Mir.Not ->
              let own tid l = ptee_shr lft tid l in
              let shr lft tid l =
                Error
                  "Calling a function with a shared reference type as a \
                   generic type argument is not yet supported"
              in
              let full_bor_content tid l =
                Error
                  "Expressing the full borrow content of a shared reference \
                   type is not yet supported"
              in
              let points_to tid l vid_op =
                let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
                Ok (PointsTo (loc, l, RegularPointsTo, pat))
              in
              Ok (own, shr, full_bor_content, points_to, None)
        in
        let ty_info =
          {
            Mir.vf_ty;
            interp =
              RustBelt.
                {
                  size = sz_expr;
                  own;
                  shr;
                  full_bor_content;
                  points_to;
                  pointee_fbc;
                };
          }
        in
        Ok ty_info

  and decode_adt_ty (adt_ty_cpn : D.ty_kind_adt_ty) =
    let def_path = translate_adt_def_id adt_ty_cpn.id in
    let kind = adt_ty_cpn.kind in
    let substs_cpn = adt_ty_cpn.substs in
    (def_path, kind, List.map decode_generic_arg substs_cpn)

  and decode_ref_ty (ref_ty_cpn : D.ty_kind_ref_ty) =
    let region_cpn = ref_ty_cpn.region in
    let region = region_cpn.id in
    let mut_cpn = ref_ty_cpn.mutability in
    let mut = match mut_cpn with Mut -> true | Not -> false in
    let ty_cpn = ref_ty_cpn.ty in
    let ty = decode_ty ty_cpn in
    (region, mut, ty)

  and decode_ty (ty_cpn : D.ty) =
    let kind_cpn = ty_cpn.kind in
    match kind_cpn with
    | Bool -> `Bool
    | Int int_ty_cpn -> `Int int_ty_cpn
    | UInt u_int_ty_cpn -> `Uint u_int_ty_cpn
    | Char -> `Char
    | Float float_ty -> `Float float_ty
    | Adt adt_ty_cpn -> `Adt (decode_adt_ty adt_ty_cpn)
    | Foreign -> `Foreign
    | RawPtr raw_ptr_ty_cpn -> `RawPtr
    | Ref ref_ty_cpn -> `Ref (decode_ref_ty ref_ty_cpn)
    | FnDef fn_def_ty_cpn -> `FnDef fn_def_ty_cpn
    | FnPtr fn_ptr_ty_cpn -> `FnPtr
    | Dynamic trait -> `Dynamic trait
    | Closure _ -> `Closure
    | CoroutineClosure -> `CoroutineClosure
    | Coroutine -> `Coroutine
    | CoroutineWitness -> `CoroutineWitness
    | Never -> `Never
    | Tuple substs_cpn -> `Tuple (List.map decode_ty substs_cpn)
    | Alias _ -> `Alias
    | Param name -> `Param name
    | Bound -> `Bound
    | Placeholder -> `Placeholder
    | Infer -> `Infer
    | Error -> `Error
    | Str -> `Str
    | Array array_ty_cpn -> `Array
    | Pattern -> `Pattern
    | Slice elem_ty_cpn -> `Slice (decode_ty elem_ty_cpn)

  and string_of_decoded_type ty =
    match ty with
    | `Bool -> "bool"
    | `Never -> "!"
    | `Adt (name, kind, args) ->
        if args = [] then name
        else
          Printf.sprintf "%s<%s>" name
            (String.concat ", " (List.map string_of_generic_arg args))
    | `Int D.I8 -> "i8"
    | `Int D.I16 -> "i16"
    | `Int D.I32 -> "i32"
    | `Int D.I64 -> "i64"
    | `Int D.I128 -> "i128"
    | `Int D.ISize -> "isize"
    | `Uint D.U8 -> "u8"
    | `Uint D.U16 -> "u16"
    | `Uint D.U32 -> "u32"
    | `Uint D.U64 -> "u64"
    | `Uint D.U128 -> "u128"
    | `Uint D.USize -> "usize"
    | _ -> "(type)"

  and extract_implicit_outlives_clauses regions ty =
    match ty with
    | `Ref (r, mut, ty) ->
        List.map (fun r' -> (r, r')) regions
        @ extract_implicit_outlives_clauses (r :: regions) ty
    | `Adt (name, kind, args) ->
        args
        |> Util.flatmap
             (extract_implicit_outlives_clauses_from_generic_arg regions)
    | _ -> []

  and translate_param_ty (name : string) (loc : Ast.loc) =
    let open Ast in
    let vf_ty = IdentTypeExpr (loc, None, name) in
    let interp : RustBelt.ty_interp =
      {
        size = SizeofExpr (loc, TypeExpr vf_ty);
        own =
          (fun t v ->
            Ok
              (Ast.ExprCallExpr
                 ( loc,
                   TypePredExpr (loc, IdentTypeExpr (loc, None, name), "own"),
                   [ LitPat t; LitPat v ] )));
        shr =
          (fun k t l ->
            Ok
              (CoefAsn
                 ( loc,
                   DummyPat,
                   ExprCallExpr
                     ( loc,
                       TypePredExpr
                         (loc, IdentTypeExpr (loc, None, name), "share"),
                       [ LitPat k; LitPat t; LitPat l ] ) )));
        full_bor_content =
          (fun tid l ->
            Ok
              (ExprCallExpr
                 ( loc,
                   TypePredExpr
                     ( loc,
                       IdentTypeExpr (loc, None, name),
                       "full_borrow_content" ),
                   [ LitPat tid; LitPat l ] )));
        points_to =
          (fun t l vid ->
            let rhs =
              match vid with None -> DummyPat | Some vid -> VarPat (loc, vid)
            in
            Ok (Ast.PointsTo (loc, l, RegularPointsTo, rhs)));
        pointee_fbc = None;
      }
    in
    Ok { Mir.vf_ty; interp }

  and translate_ty_const_kind (ck_cpn : D.const_kind) (loc : Ast.loc) =
    let open VfMirRd.ConstKind in
    match ck_cpn with
    | Param _ -> Ast.static_error loc "Todo: ConstKind::Param" None
    | Infer -> Ast.static_error loc "Todo: ConstKind::Infer" None
    | Bound -> Ast.static_error loc "Todo: ConstKind::Bound" None
    | Placeholder -> Ast.static_error loc "Todo: ConstKind::Placeholder" None
    | Alias -> Ast.static_error loc "Todo: ConstKind::Alias" None
    | Value v_cpn -> (
        let open VfMirRd.Value in
        let* ty = translate_ty v_cpn.ty loc in
        let val_tree = v_cpn.val_tree in
        let open VfMirRd.ValTree in
        match val_tree with
        | Leaf scalar_int_cpn ->
            translate_scalar_int scalar_int_cpn ty.vf_ty loc
        | Branch _ -> failwith "Todo: ConstKind::ValTree::Branch")
    | Error -> Ast.static_error loc "Todo: ConstKind::Error" None
    | Expr -> Ast.static_error loc "Todo: ConstKind::Expr" None

  and translate_ty_const (ty_const_cpn : D.ty_const) (loc : Ast.loc) =
    translate_ty_const_kind ty_const_cpn.kind loc

  and translate_array_ty (array_ty_cpn : D.ty_kind_array_ty) (loc : Ast.loc) =
    let elem_ty_cpn = array_ty_cpn.elem_ty in
    let* elem_ty_info = translate_ty elem_ty_cpn loc in
    let elem_ty = elem_ty_info.vf_ty in
    let len_cpn = array_ty_cpn.size in
    let* (CastExpr (_, _, IntLit (_, len, _, _, _))) =
      translate_ty_const len_cpn loc
    in
    let vf_ty =
      Ast.StaticArrayTypeExpr
        (loc, elem_ty, LiteralConstTypeExpr (loc, Z.of_big_int len))
    in
    let size = Ast.SizeofExpr (loc, TypeExpr vf_ty) in
    let is_r23_u64_array3 =
      !r23_source_array3_interp_active &&
      decode_ty elem_ty_cpn = `Uint D.U64 &&
      Big_int.compare_big_int len (Big_int.big_int_of_int 3) = 0
    in
    let own tid vs =
      if is_r23_u64_array3 then
        Ok
          (Ast.CallExpr
             (loc, "r23_u64_array3_own", [], [],
              [Ast.LitPat tid; Ast.LitPat vs], Ast.Static))
      else Error "Expressing ownership of an array is not yet supported"
    in
    let full_bor_content t l =
      if is_r23_u64_array3 then
        Ok
          (Ast.CallExpr
             (loc, "r23_u64_array3_fbc", [], [],
              [Ast.LitPat t; Ast.LitPat l], Ast.Static))
      else
        Error
          "Expressing the full borrow content of an array is not yet supported"
    in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (Ast.PointsTo (loc, l, RegularPointsTo, pat))
    in
    let interp =
      RustBelt.
        {
          size;
          own;
          shr =
            (fun k t l ->
              Error
                "Expressing the shared ownership of an array is not yet \
                 supported");
          full_bor_content;
          points_to;
          pointee_fbc = None;
        }
    in
    Ok { Mir.vf_ty; interp }

  and translate_slice_ty (elem_ty_cpn : D.ty) (loc : Ast.loc) =
    let* elem_ty_info = translate_ty elem_ty_cpn loc in
    let elem_ty = elem_ty_info.vf_ty in
    let vf_ty = Ast.SliceTypeExpr (loc, elem_ty) in
    let size = Ast.SizeofExpr (loc, TypeExpr vf_ty) in
    let own tid vs =
      Error "Expressing ownership of a slice is not yet supported"
    in
    let full_bor_content t l =
      Error
        "Expressing the full borrow content of a slice is not yet supported"
    in
    let points_to tid l vid_op =
      let* pat = RustBelt.Aux.vid_op_to_var_pat vid_op loc in
      Ok (Ast.PointsTo (loc, l, RegularPointsTo, pat))
    in
    let interp =
      RustBelt.
        {
          size;
          own;
          shr =
            (fun k t l ->
              Error
                "Expressing the shared ownership of a slice is not yet \
                 supported");
          full_bor_content;
          points_to;
          pointee_fbc = None;
        }
    in
    Ok { Mir.vf_ty; interp }

  and translate_ty (ty_cpn : D.ty) (loc : Ast.loc) =
    let open Ast in
    let kind_cpn = ty_cpn.kind in
    match kind_cpn with
    | Bool -> Ok (bool_ty_info loc)
    | Int int_ty_cpn -> translate_int_ty int_ty_cpn loc
    | UInt u_int_ty_cpn -> translate_u_int_ty u_int_ty_cpn loc
    | Char -> Ok (char_ty_info loc)
    | Float float_ty ->
        Ast.static_error loc "Floating point types are not yet supported" None
    | Adt adt_ty_cpn -> translate_adt_ty adt_ty_cpn loc
    | Foreign -> Ast.static_error loc "Foreign types are not yet supported" None
    | RawPtr raw_ptr_ty_cpn -> translate_raw_ptr_ty raw_ptr_ty_cpn loc
    | Ref ref_ty_cpn -> translate_ref_ty ref_ty_cpn loc
    | FnDef fn_def_ty_cpn -> translate_fn_def_ty fn_def_ty_cpn loc
    | FnPtr fn_ptr_ty_cpn -> translate_fn_ptr_ty fn_ptr_ty_cpn loc
    | Dynamic _ -> Ast.static_error loc "Dynamic types are not yet supported" None
    | Closure closure_ty_cpn ->
        (* This translation is sound provided that closures are consumed only by calls and such calls are rejected by VeriFast. *)
        let vf_ty = Ast.ManifestTypeExpr (loc, Ast.StructType (TrTyTuple.tuple0_name, [])) in
        Ok { Mir.vf_ty; interp = RustBelt.emp_ty_interp loc }
    | CoroutineClosure ->
        Ast.static_error loc "Coroutine closure types are not yet supported"
          None
    | Coroutine ->
        Ast.static_error loc "Coroutine types are not yet supported" None
    | CoroutineWitness ->
        Ast.static_error loc "Coroutine witness types are not yet supported"
          None
    | Never -> Ok (never_ty_info loc)
    | Tuple tys_cpn -> translate_tuple_ty tys_cpn loc
    | Alias alias_ty_cpn -> translate_alias_ty alias_ty_cpn loc
    | Param name -> translate_param_ty name loc
    | Bound -> Ast.static_error loc "Bound types are not yet supported" None
    | Placeholder ->
        Ast.static_error loc "Placeholder types are not yet supported" None
    | Infer -> Ast.static_error loc "Infer types are not yet supported" None
    | Error -> Ast.static_error loc "Error types are not yet supported" None
    | Str -> Ast.static_error loc "Str types are not yet supported" None
    | Array array_ty_cpn -> translate_array_ty array_ty_cpn loc
    | Pattern -> Ast.static_error loc "Pattern types are not yet supported" None
    | Slice ty_cpn -> translate_slice_ty ty_cpn loc

  let translate_decoded_ty = translate_ty

  let translate_ty (ty_cpn : TyRd.t) (loc : Ast.loc) =
    translate_ty (D.decode_ty ty_cpn) loc

  type body_tr_defs_ctx = {
    selected_drops : (string * string * string) list;
    generated_glue : generated_glue_binding option;
    adt_defs : Mir.adt_def_tr list;
    ghost_decl_map : (string * Ast.decl) list;
    directives : Mir.annot list;
    fn_specializer : string -> D.generic_arg list -> string * D.generic_arg list;
    r23_checked_slice_helper : BodyRd.t option;
  }

  and generated_glue_binding = {
    glue_key : string;
    glue_guard : string;
    glue_selected_path : string;
    glue_selected_hash : string;
    glue_raw_trait_path : string;
    glue_raw_trait_hash : string;
    glue_method_body : BodyRd.t;
  }

  type r23_pure_slice_projection = {
    r23_projection_input : string;
    r23_projection_output : string;
    r23_projection_steps : string list;
    r23_projection_trace : string list;
    r23_projection_local_count : int;
    r23_projection_local_mutabilities : string list;
    r23_projection_block_count : int;
    r23_projection_statement_count : int;
  }

  (* Normalize only a straight-line, one-input body made of pointer casts, or
     the exact mutable receiver-dereference raw-pointer step followed by its
     single data-pointer cast. This structural check rejects other operations
     that could access memory, call code, or branch. Reference lifetime
     spellings are omitted from the type key; mutability and pointee types stay. *)
  let r23_projection_mutability mutability_cpn =
    match MutabilityRd.get mutability_cpn with
    | MutabilityRd.Mut -> "mut"
    | MutabilityRd.Not -> "const"

  let r23_projection_type_key loc generic_bindings ty =
    let fail () = Ast.static_error loc
      "R23 callee projection contains an unsupported or unbound type" None in
    let rec key ty =
      match TyKindRd.get (TyRd.kind_get ty) with
      | TyKindRd.Ref ref_ty ->
          "ref-" ^ r23_projection_mutability
            (RefTyRd.mutability_get ref_ty) ^ "(" ^
          key (RefTyRd.ty_get ref_ty) ^ ")"
      | TyKindRd.RawPtr raw_ty ->
          "raw-" ^ r23_projection_mutability
            (RawPtrTyRd.mutability_get raw_ty) ^ "(" ^
          key (RawPtrTyRd.ty_get raw_ty) ^ ")"
      | TyKindRd.Slice elem -> "slice(" ^ key elem ^ ")"
      | TyKindRd.Param name ->
          (match List.assoc_opt name generic_bindings with
           | Some resolved -> resolved
           | None -> fail ())
      | _ ->
          (match decode_ty (D.decode_ty ty) with
           | `Uint D.U64 -> "u64"
           | _ -> fail ())
    in
    key ty

  let r23_pure_projection loc ~generic_bindings ~inputs ~output ~local_decls
      ~basic_blocks ~reported_block_count ~reported_statement_count =
    let fail reason = Ast.static_error loc
      ("R23 callee projection refused: " ^ reason) None in
    let block_count = List.length basic_blocks in
    let statement_count = List.fold_left (fun total block ->
      total + List.length (BasicBlockRd.statements_get_list block))
      0 basic_blocks in
    if block_count <> reported_block_count || statement_count <> reported_statement_count then
      fail "reported body counts do not cover the complete block and statement lists";
    if block_count <> 1 || List.length inputs <> 1 then
      fail "projection is not a single-input straight-line body";
    let local_types = List.map (fun local ->
      let id = LocalDeclIdRd.name_get (LocalDeclRd.id_get local) in
      (id, LocalDeclRd.ty_get local)) local_decls in
    let local_mutabilities = List.map (fun local ->
      r23_projection_mutability (LocalDeclRd.mutability_get local)) local_decls in
    if List.length (List.sort_uniq String.compare (List.map fst local_types)) <>
       List.length local_types then
      fail "body has duplicate local declarations";
    let local_ty id = match List.assoc_opt id local_types with
      | Some ty -> ty
      | None -> fail "projection operand or destination has no local declaration" in
    let local_index id =
      let rec find index = function
        | [] -> fail "projection statement refers to an undeclared local"
        | (candidate, _) :: rest ->
            if candidate = id then index else find (index + 1) rest in
      find 0 local_types in
    let input_local, output_local = match local_decls with
      | ret :: arg :: _ ->
          let ret_id = LocalDeclIdRd.name_get (LocalDeclRd.id_get ret)
          and arg_id = LocalDeclIdRd.name_get (LocalDeclRd.id_get arg) in
          if ret_id <> "_0" || arg_id <> "_1" then
            fail "MIR return and receiver local order is noncanonical";
          (arg_id, ret_id)
      | _ -> fail "body lacks return and receiver locals" in
    let input_key = r23_projection_type_key loc generic_bindings (List.hd inputs)
    and output_key = r23_projection_type_key loc generic_bindings output in
    let local_input_key = r23_projection_type_key loc generic_bindings (local_ty input_local)
    and local_output_key = r23_projection_type_key loc generic_bindings (local_ty output_local) in
    if input_key <> "ref-mut(slice(u64))" || local_input_key <> input_key ||
       output_key <> "raw-mut(u64)" || local_output_key <> output_key then
      fail "signature is not exactly &mut [u64] -> *mut u64";
    let block = List.hd basic_blocks in
    if BasicBlockRd.is_cleanup_get block then
      fail "projection body contains a cleanup block";
    (match TerminatorKindRd.get
       (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
     | TerminatorKindRd.Return -> ()
     | _ -> fail "projection body has a call, branch, or non-Return terminator");
    let provenance = ref [input_local] in
    let assigned = ref [] in
    let step_edges = ref [] in
    let statements = BasicBlockRd.statements_get_list block in
    let storage_locals = List.fold_left (fun locals stmt ->
      let id = match StatementKindRd.get (StatementRd.kind_get stmt) with
        | StatementKindRd.StorageLive local
        | StatementKindRd.StorageDead local ->
            Some (LocalDeclIdRd.name_get local)
        | _ -> None in
      match id with
      | Some id when not (List.mem id locals) -> id :: locals
      | _ -> locals) [] statements in
    List.iter (fun id ->
      ignore (local_index id);
      if id = input_local || id = output_local then
        fail "storage markers target the receiver or return local";
      if not (String.starts_with ~prefix:"raw-"
          (r23_projection_type_key loc generic_bindings (local_ty id))) then
        fail "storage markers target a non-pointer temporary") storage_locals;
    let storage_states = ref (List.map (fun id -> id, false) storage_locals) in
    let storage_started = ref [] in
    let storage_ended = ref [] in
    let steps = ref [] in
    let raw_ptr_local = ref None in
    let cast_count = ref 0 in
    (* Locals with no storage markers are live for the whole body. For marked
       temporaries, accept only one explicit, balanced Live/Dead pair. *)
    let local_is_live id = match List.assoc_opt id !storage_states with
      | Some live -> live
      | None -> true in
    let set_storage_live id live =
      storage_states := List.map (fun (candidate, old_live) ->
        candidate, if candidate = id then live else old_live) !storage_states in
    let trace = List.map (fun stmt ->
      match StatementKindRd.get (StatementRd.kind_get stmt) with
      | StatementKindRd.StorageLive local ->
          let id = LocalDeclIdRd.name_get local in
          if List.mem id !storage_started || local_is_live id then
            fail "storage local has a duplicate or overlapping Live event";
          storage_started := id :: !storage_started;
          set_storage_live id true;
          "storage-live:" ^ string_of_int (local_index id)
      | StatementKindRd.StorageDead local ->
          let id = LocalDeclIdRd.name_get local in
          if not (List.mem id !storage_started) ||
             List.mem id !storage_ended || not (local_is_live id) then
            fail "storage local has an unmatched or overlapping Dead event";
          if not (List.mem id !provenance) then
            fail "storage local becomes dead before receiving a projection value";
          storage_ended := id :: !storage_ended;
          set_storage_live id false;
          "storage-dead:" ^ string_of_int (local_index id)
      | StatementKindRd.Assign data ->
          let lhs = AssignDataRd.lhs_place_get data in
          if PlaceRd.projection_get_list lhs <> [] then
            fail "projection writes through a place projection";
          let dst = LocalDeclIdRd.name_get (PlaceRd.local_get lhs) in
          let rvalue = AssignDataRd.rhs_rvalue_get data in
          (match RvalueRd.get rvalue with
           | RvalueRd.RawPtr raw_ptr_data ->
               if !raw_ptr_local <> None || !assigned <> [] then
                 fail "raw pointer address is not the first value projection step";
               (match OptionRd.get (RawPtrDataRd.raw_ptr_kind_get raw_ptr_data) with
                | OptionRd.Something kind_ptr ->
                    let kind_data = VfMirRd.of_pointer kind_ptr in
                    if kind_data = None then
                      fail "raw pointer kind metadata payload is absent";
                    (match RawPtrKindRd.get kind_data with
                     | RawPtrKindRd.Mut -> ()
                     | RawPtrKindRd.Const
                     | RawPtrKindRd.FakeForPtrMetadata ->
                         fail "raw pointer kind is not exact Mut"
                     | _ -> fail "raw pointer kind is unknown")
                | OptionRd.Nothing ->
                    fail "raw pointer kind metadata is absent");
               if MutabilityRd.get (RawPtrDataRd.mutability_get raw_ptr_data) <>
                    MutabilityRd.Mut then
                 fail "raw pointer mutability is not Mut";
               let place = RawPtrDataRd.place_get raw_ptr_data in
               let is_mutable_ref = match PlaceKindRd.get (PlaceRd.kind_get place) with
                 | PlaceKindRd.MutableRef -> true
                 | _ -> false in
               let is_single_deref = match PlaceRd.projection_get_list place with
                 | [elem] ->
                     (match PlaceElementRd.get elem with
                      | PlaceElementRd.Deref -> true
                      | _ -> false)
                 | _ -> false in
               if LocalDeclIdRd.name_get (PlaceRd.local_get place) <> input_local ||
                  not is_mutable_ref || not is_single_deref then
                 fail "raw pointer place is not exactly a mutable receiver dereference";
               let source_key = local_input_key
               and target_key = r23_projection_type_key loc generic_bindings (local_ty dst) in
               if source_key <> "ref-mut(slice(u64))" ||
                  target_key <> "raw-mut(slice(u64))" || dst = input_local ||
                  dst = output_local || not (local_is_live input_local) ||
                  not (local_is_live dst) then
                 fail "raw pointer step has the wrong receiver, destination type, or storage state";
               raw_ptr_local := Some dst;
               provenance := dst :: !provenance;
               assigned := dst :: !assigned;
               step_edges := !step_edges @ [(input_local, dst)];
               let edge = source_key ^ "->" ^ target_key ^ ":raw-ptr-mut-deref" in
               steps := edge :: !steps;
               "raw-ptr-mut-deref:" ^ string_of_int (local_index input_local) ^ ":" ^
               string_of_int (local_index dst) ^ ":" ^ edge
           | RvalueRd.Cast cast_data ->
               let src = match OperandRd.get (CastDataRd.operand_get cast_data) with
                 | OperandRd.Copy place | OperandRd.Move place
                   when PlaceRd.projection_get_list place = [] ->
                     LocalDeclIdRd.name_get (PlaceRd.local_get place)
                 | _ -> fail "projection cast source is not a bare local" in
               if not (List.mem src !provenance) || not (local_is_live src) ||
                  not (local_is_live dst) ||
                  List.mem dst !assigned || dst = input_local then
                 fail "projection cast uses a dead local or is not a unique dataflow from the receiver";
               let source_type = match OptionRd.get
                   (CastDataRd.source_ty_get cast_data) with
                 | OptionRd.Something ptr -> VfMirRd.of_pointer ptr
                 | _ -> fail "projection cast omits its typed source" in
               let target_type = CastDataRd.ty_get cast_data in
               let source_key = r23_projection_type_key loc generic_bindings source_type
               and target_key = r23_projection_type_key loc generic_bindings target_type
               and local_source_key = r23_projection_type_key loc generic_bindings (local_ty src)
               and local_target_key = r23_projection_type_key loc generic_bindings (local_ty dst) in
               if source_key <> local_source_key || target_key <> local_target_key ||
                  not (String.starts_with ~prefix:"raw-mut(" target_key) then
                 fail "cast source/target types disagree with the local declarations";
               let cast_kind = match CastKindRd.get (CastDataRd.kind_get cast_data) with
                 | CastKindRd.PtrToPtr -> "ptr-to-ptr"
                 | CastKindRd.PointerCoercion ->
                     (match OptionRd.get
                       (CastDataRd.pointer_coercion_data_get cast_data) with
                      | OptionRd.Something ptr ->
                          let coercion = VfMirRd.of_pointer ptr in
                          (match PointerCoercionKindRd.get
                              (PointerCoercionDataRd.kind_get coercion) with
                           | PointerCoercionKindRd.Unsize -> "unsize"
                           | _ -> fail "unsupported pointer coercion in projection")
                      | _ -> fail "pointer coercion omits its typed kind")
                 | _ -> fail "projection contains a non-pointer cast" in
               (match !raw_ptr_local with
                | None -> ()
                | Some raw_local ->
                    if src <> raw_local || dst <> output_local || !cast_count <> 0 ||
                       source_key <> "raw-mut(slice(u64))" ||
                       target_key <> "raw-mut(u64)" || cast_kind <> "ptr-to-ptr" then
                      fail "raw slice pointer is not followed by exactly one PtrToPtr data-pointer cast");
               incr cast_count;
               provenance := dst :: !provenance;
               assigned := dst :: !assigned;
               step_edges := !step_edges @ [(src, dst)];
               let edge = source_key ^ "->" ^ target_key ^ ":" ^ cast_kind in
               steps := edge :: !steps;
               "cast:" ^ string_of_int (local_index src) ^ ":" ^
               string_of_int (local_index dst) ^ ":" ^ edge
           | _ -> fail "projection contains a non-cast rvalue")
      | _ -> fail "projection contains a non-assignment statement")
      statements in
    let steps = List.rev !steps in
    (match !raw_ptr_local with
     | Some _ when !cast_count <> 1 ->
         fail "raw pointer projection lacks exactly one final PtrToPtr cast"
     | _ -> ());
    if List.sort_uniq String.compare !storage_started <>
         List.sort_uniq String.compare storage_locals ||
       List.sort_uniq String.compare !storage_ended <>
         List.sort_uniq String.compare storage_locals then
      fail "storage marker locals do not have one complete Live/Dead pair";
    if steps = [] || List.hd !assigned <> output_local ||
       not (List.mem output_local !provenance) then
      fail "returned raw pointer is not the final cast result";
    let rec linear_chain expected = function
      | [] -> expected = output_local
      | (src, dst) :: rest ->
          src = expected &&
          linear_chain dst rest in
    if not (linear_chain input_local !step_edges) then
      fail "cast results do not form one complete linear projection from the receiver";
    if List.length local_decls <> List.length steps + 1 ||
       List.length !assigned <> List.length local_decls - 1 then
      fail "body contains an unused, uninitialized, or unassigned local";
    { r23_projection_input = input_key;
      r23_projection_output = output_key;
      r23_projection_steps = steps;
      r23_projection_trace = trace;
      r23_projection_local_count = List.length local_decls;
      r23_projection_local_mutabilities = local_mutabilities;
      r23_projection_block_count = block_count;
      r23_projection_statement_count = statement_count }

  let r23_verify_checked_slice_helper loc projection helper_body =
    let fail reason = Ast.static_error loc
      ("R23 checked slice helper equivalence refused: " ^ reason) None in
    let projection = VfMirRd.of_pointer projection in
    let callee_name = canonicalize_item_name
      (R23SliceProjectionRd.callee_name_get projection) in
    if callee_name <> "std::slice::<impl [T]>::as_mut_ptr" then
      fail "descriptor names a different standard callee";
    if R23SliceProjectionRd.callee_def_path_hash_get projection = "" ||
       R23SliceProjectionRd.mir_phase_get projection = "" ||
       R23SliceProjectionRd.mir_debug_hash_get projection = "" then
      fail "descriptor lacks standard callee identity or MIR phase/hash";
    if R23SliceProjectionRd.unsupported_reason_get projection <> "" ||
       R23SliceProjectionRd.unavailable_reason_get projection <> "" then
      fail "exporter marked the standard callee body unsupported or unavailable";
    let generic_bindings =
      R23SliceProjectionRd.generic_bindings_get_list projection in
    let u64_type_binding = List.filter_map (fun binding ->
      let name = R23SliceProjectionGenericBindingRd.id_get binding in
      match (D.decode_generic_arg
        (R23SliceProjectionGenericBindingRd.value_get binding)).kind with
      | Type ty when name = "T" && decode_ty ty = `Uint D.U64 ->
          Some (name, "u64")
      | _ -> None) generic_bindings in
    if List.length generic_bindings <> 1 ||
       u64_type_binding <> [ ("T", "u64") ] then
      fail "standard callee generic binding is not exactly T = u64";
    let std_projection = r23_pure_projection loc
      ~generic_bindings:u64_type_binding
      ~inputs:(R23SliceProjectionRd.inputs_get_list projection)
      ~output:(R23SliceProjectionRd.output_get projection)
      ~local_decls:(R23SliceProjectionRd.local_decls_get_list projection)
      ~basic_blocks:(R23SliceProjectionRd.basic_blocks_get_list projection)
      ~reported_block_count:(Stdint.Uint32.to_int
        (R23SliceProjectionRd.block_count_get projection))
      ~reported_statement_count:(Stdint.Uint32.to_int
        (R23SliceProjectionRd.statement_count_get projection)) in
    let helper_name = TrName.translate_def_path
      (BodyRd.def_path_get helper_body) in
    if not (helper_name = "r23_checked_slice_as_mut_ptr" ||
            String.ends_with ~suffix:"::r23_checked_slice_as_mut_ptr" helper_name) ||
       BodyRd.def_path_hash_get helper_body = "" ||
       BodyRd.captured_mir_phase_get helper_body = "" ||
       BodyRd.captured_mir_hash_get helper_body = "" ||
       Capnp.Array.is_empty
         (ContractRd.annotations_get (BodyRd.contract_get helper_body)) then
      fail "checked helper identity, captured MIR binding, or proof contract is missing";
    if BodyRd.generics_get_list helper_body <> [] then
      fail "checked helper has early-bound generics; expected only its source lifetime";
    let helper_hir_params = HirGenericsRd.params_get_list
      (BodyRd.hir_generics_get helper_body) in
    (match helper_hir_params with
     | [param] ->
         let name = match HirGenericParamNameRd.get
             (HirGenericParamRd.name_get param) with
           | HirGenericParamNameRd.Plain ident ->
               SymbolRd.name_get (IdentRd.name_get ident)
           | HirGenericParamNameRd.Fresh _
           | HirGenericParamNameRd.Undefined _ -> "" in
         let kind = HirGenericParamKindRd.get
           (HirGenericParamRd.kind_get param) in
         if name <> "'a" || kind <> HirGenericParamKindRd.Lifetime then
           fail "checked helper source HIR signature is not exactly generic over lifetime 'a"
     | _ ->
         fail "checked helper source HIR signature must declare only lifetime 'a");
    let helper_projection = r23_pure_projection loc ~generic_bindings:[]
      ~inputs:(BodyRd.inputs_get_list helper_body)
      ~output:(BodyRd.output_get helper_body)
      ~local_decls:(BodyRd.local_decls_get_list helper_body)
      ~basic_blocks:(BodyRd.basic_blocks_get_list helper_body)
      ~reported_block_count:(List.length (BodyRd.basic_blocks_get_list helper_body))
      ~reported_statement_count:(List.fold_left (fun total block ->
        total + List.length (BasicBlockRd.statements_get_list block)) 0
        (BodyRd.basic_blocks_get_list helper_body)) in
    if std_projection <> helper_projection then
      fail "checked helper's complete typed cast body differs from the actual std callee";
    helper_name

  type var_id_trs_entry = { id : string; internal_name : string }
  type var_id_trs_map = var_id_trs_entry list

  type first_callback_plan = {
    first_close_loc : Ast.loc;
    first_scope_end_loc : Ast.loc;
    first_lft : string;
    first_close_stmt : Ast.stmt;
    first_recover_stmt : Ast.stmt;
  }

  type late_callback_plan = {
    late_original_decl_loc : Ast.loc;
    late_begin_loc : Ast.loc;
    late_close_loc : Ast.loc;
    late_scope_end_loc : Ast.loc;
    late_recover_loc : Ast.loc;
    late_lft : string;
    late_close_stmt : Ast.stmt;
    late_recover_stmt : Ast.stmt;
  }

  type r23_source_array_adapter_plan = {
    r23_pre_marker_loc : Ast.loc;
    r23_pre_marker_end : Ast.loc;
    r23_post_marker_loc : Ast.loc;
    r23_post_marker_end : Ast.loc;
    r23_pre_stmt : Ast.stmt;
    r23_post_stmt : Ast.stmt;
    r23_lifetime_token : string;
    r23_values_local : string;
    r23_begin_local : string;
    r23_values_state : string;
    mutable r23_ref_local : string option;
    mutable r23_unsize_local : string option;
    mutable r23_ref_seen : bool;
    mutable r23_unsize_seen : bool;
    mutable r23_call_seen : bool;
    mutable r23_projection_approved : bool;
    mutable r23_checked_helper_name : string option;
    mutable r23_scoped_local_decls : Ast.stmt list;
    mutable r23_scope_decls_inserted : bool;
    mutable r23_unwind_epilogue : Ast.stmt list option;
    r23_unwind_label : string;
  }

  type r9_guard_return_plan = {
    r9_guard_return_loc : Ast.loc;
    r9_guard_return_end_loc : Ast.loc;
    r9_guard_return_commands : Ast.stmt list;
    r9_guard_return_key : string;
    r9_guard_return_path : string;
    r9_guard_return_hash : string;
    r9_guard_return_guard : string;
    r9_guard_return_edges : (string * string * bool * string) list;
  }

  let fresh_first_callback_stmt = function
    | Ast.PureStmt (loc, Ast.BlockStmt (block_loc, decls, stmts, close_loc, _)) ->
        Ast.PureStmt (loc,
          Ast.BlockStmt (block_loc, decls, stmts, close_loc, ref []))
    | _ -> invalid_arg "First callback command block has the wrong AST shape"

  (* Shared by body-level admission and terminator translation. *)
  let translate_basic_block_id (bblock_id_cpn : BasicBlockIdRd.t) =
    Stdint.Uint32.to_string (BasicBlockIdRd.index_get bblock_id_cpn)

  module TranslatorArgs = Args

  module TrBody (Args : sig
    val var_id_trs_map_ref : var_id_trs_map ref
    val ghost_stmts : Ast.stmt list
    val body_imp_loc : Ast.loc
    val body_name : string
    val body_def_hash : string
    val body_mir_fingerprint : string
    val body_mir_phase : string
    val body_tr_defs_ctx : body_tr_defs_ctx
    val is_generated_glue : bool
    val strict_lft_scope_ends : (Ast.loc * string) list
    val callback_close : (Ast.loc * string * Ast.stmt) option
    val callback_recover : Ast.stmt option
    val callback_scope_start : Ast.loc option
    val first_callback : first_callback_plan option
    val late_callback : late_callback_plan option
    val r23_source_array_adapter : r23_source_array_adapter_plan option
    val r9_guard_return : r9_guard_return_plan option
    val r19_unwind_cleanup : (Ast.loc * Ast.stmt) option
  end) =
  struct
    type hrtb_callback_referent = HrtbParam of string | HrtbU64

    module State = struct
      let var_id_trs_map_ref = Args.var_id_trs_map_ref
      let ghost_stmts = ref Args.ghost_stmts
      let body_imp_loc = Args.body_imp_loc
      let body_tr_defs_ctx = Args.body_tr_defs_ctx
      let strict_lft_scope_ends = Args.strict_lft_scope_ends
      let callback_close = Args.callback_close
      let callback_recover = Args.callback_recover
      let callback_scope_start = Args.callback_scope_start
      let first_callback = Args.first_callback
      let late_callback = Args.late_callback
      let r23_source_array_adapter = Args.r23_source_array_adapter
      let r23_adapter_ref_assignment = ref false
      let r23_adapter_unsize_assignment = ref false
      let r23_adapter_post_bridge : Ast.stmt option ref = ref None
      let r9_guard_return = Args.r9_guard_return
      let r9_guard_return_used : (string * string * bool * string) list ref = ref []
      let r19_unwind_cleanup = Args.r19_unwind_cleanup
      let r19_unwind_cleanup_used = ref false
      let first_callback_used = ref false
      let first_callback_call_loc = ref None
      let first_callback_normal_target = ref None
      let first_fnmut_calls :
          (Ast.loc * [ `Continue | `Cleanup | `Other ]) list ref = ref []
      let first_callback_unwind_label = "#merge_first_callback_unwind"
      let late_callback_call : (Ast.loc * string * string) option ref = ref None
      let late_callback_used = ref false
      let callback_used = ref false
      let callback_call_loc = ref None
      let fnmut_call_count = ref 0
      let callback_unwind_label = "#merge_callback_unwind_epilogue"
      let selected_resume_targets : string list ref = ref []
      let translating_selected_resume = ref false
      let current_block = ref ""
      let current_is_cleanup = ref false
      let generated_glue = Args.body_tr_defs_ctx.generated_glue
      let is_generated_glue = Args.is_generated_glue
      let hrtb_fnmut_output_bounds :
          (string * hrtb_callback_referent) list ref = ref []
      let pending_hrtb_projection_eq : Ast.stmt list ref = ref []

      let fetch_ghost_stmts_before (l : Ast.loc0) =
        let* gs_before, gs_rem =
          ListAux.try_partition
            (fun g ->
              let lg = Ast.lexed_loc (Ast.stmt_loc g) in
              let* cmp = LocAux.try_compare_loc lg l in
              Ok (cmp < 0))
            !ghost_stmts
        in
        ghost_stmts := gs_rem;
        Ok gs_before

      let get_adt_def adt_name =
        Ok
          (List.find_opt
             (fun ({ name } : Mir.adt_def_tr) -> name = adt_name)
             body_tr_defs_ctx.adt_defs)
    end

    let translate_local_decl_id_ (name : string) =
      let id = TrName.tag_internal name in
      match
        List.find_opt
          (fun ({ id = id1; _ } : var_id_trs_entry) -> id = id1)
          !State.var_id_trs_map_ref
      with
      | None -> id
      | Some { id; internal_name } -> internal_name

    let translate_local_decl_id (local_decl_id_cpn : LocalDeclIdRd.t) =
      translate_local_decl_id_ (LocalDeclIdRd.name_get local_decl_id_cpn)
    
    let translate_local_decl (local_decl_cpn : LocalDeclRd.t) =
      let open LocalDeclRd in
      let mutability_cpn = mutability_get local_decl_cpn in
      let* mutability = translate_mutability mutability_cpn in
      let id_cpn = id_get local_decl_cpn in
      let id = translate_local_decl_id id_cpn in
      let src_info_cpn = source_info_get local_decl_cpn in
      let* { Mir.span = loc; Mir.scope } = translate_source_info src_info_cpn in
      let ty_cpn = ty_get local_decl_cpn |> D.decode_ty in
      Rocq_writer.rocq_print_tuple TranslatorArgs.rocq_writer begin fun () ->
        Rocq_writer.rocq_print_tuple_element TranslatorArgs.rocq_writer begin fun () ->
          Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer id
        end;
        Rocq_writer.rocq_print_tuple_element TranslatorArgs.rocq_writer begin fun () ->
          Rocq_writer.rocq_print_small_record TranslatorArgs.rocq_writer begin fun () ->
            Rocq_writer.rocq_print_small_record_field TranslatorArgs.rocq_writer "mutability" begin fun () ->
              Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer
                begin match mutability with
                | Mir.Mut -> "Mut"
                | Mir.Not -> "Not"
                end
            end;
            Rocq_writer.rocq_print_small_record_field TranslatorArgs.rocq_writer "ty" begin fun () ->
              Rocq_writer.rocq_print_data TranslatorArgs.rocq_writer Vf_mir_rocq.rocq_print_ty ty_cpn
            end;
          end
        end
      end;
      let ty_info =
        lazy
          (match translate_decoded_ty ty_cpn loc with
          | Ok ty -> ty
          | _ ->
              Ast.static_error loc
                "The type of this local variable is not yet supported" None)
      in
      let local_decl : Mir.local_decl = { mutability; id; ty = ty_info; loc } in
      Ok local_decl

    let translate_to_vf_local_decl loc
        ({ mutability = mut; id; ty = (lazy ty_info) } : Mir.local_decl) =
      let ty = ty_info.vf_ty in
      Ast.DeclStmt
        ( loc,
          [
            ( loc,
              Some (match mut with Mut -> ty | Not -> ConstTypeExpr (loc, ty)),
              id,
              None,
              ( (* indicates whether address is taken *) ref false,
                (* pointer to enclosing block's list of variables whose address is taken *)
                ref None ) );
          ] )

    type place_element =
      | Deref
      | Field of string option * int
      | Downcast of int
      | BoxAsNonNull

    let decode_place_element (place_elm : PlaceElementRd.t) : place_element =
      let open PlaceElementRd in
      match get place_elm with
      | Deref ->
        Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "Deref";
        Deref
      | BoxAsNonNull _ ->
        Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "BoxAsNonNull";
        BoxAsNonNull
      | Field field_data_cpn ->
          let open FieldData in
          let index = index_get field_data_cpn in
          let name_cpn = name_get field_data_cpn in
          let name =
            match OptionRd.get name_cpn with
            | Nothing -> None
            | Something name_cpn ->
                Some (SymbolRd.name_get (VfMirRd.of_pointer name_cpn))
          in
          Field (name, Stdint.Uint32.to_int index)
      | Downcast variant_index -> Downcast (Stdint.Uint32.to_int variant_index)

    let translate_projection (loc : Ast.loc) (elems : place_element list)
        (e : Ast.expr) (e_is_mutable : bool) :
        Ast.expr * bool (* result is mutable *) =
      let rec iter elems =
        match elems with
        | [] -> (e, e_is_mutable)
        | Deref :: elems ->
            let e1, e1_is_mutable = iter elems in
            (Ast.Deref (loc, e1), true)
        | Field (_, field_idx) :: Downcast variant_idx :: elems ->
            let e1, e1_is_mutable = iter elems in
            ( Ast.CallExpr
                ( loc,
                  "#inductive_projection",
                  [],
                  [],
                  [
                    LitPat e1;
                    LitPat (WIntLit (loc, Big_int.big_int_of_int variant_idx));
                    LitPat (WIntLit (loc, Big_int.big_int_of_int field_idx));
                  ],
                  Static ),
              e1_is_mutable )
        | Field (name, field_idx) :: elems ->
            let name = match name with Some name -> name | None -> string_of_int field_idx in
            let e1, e1_is_mutable = iter elems in
            (Ast.Select (loc, e1, name), e1_is_mutable)
        | Downcast _ :: _ -> failwith "Not yet supported: Downcast _::_"
        | BoxAsNonNull :: _ -> Ast.EmpAsn loc, false (* Dummy result; never used *)
      in
      iter elems

    let translate_place (place_cpn : PlaceRd.t) (loc : Ast.loc) :
        (Ast.expr * bool (* the place is mutable *), _) result =
      let open PlaceRd in
      Rocq_writer.rocq_print_tuple TranslatorArgs.rocq_writer @@ fun () ->
      let id_cpn = local_get place_cpn in
      let local_is_mutable = local_is_mutable_get place_cpn in
      let id = translate_local_decl_id id_cpn in
      Rocq_writer.rocq_print_tuple_element TranslatorArgs.rocq_writer begin fun () ->
        Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer id
      end;
      let projection_cpn = projection_get_list place_cpn in
      let place_elems =
        Rocq_writer.rocq_print_tuple_element TranslatorArgs.rocq_writer @@ fun () ->
          Rocq_writer.rocq_print_small_list TranslatorArgs.rocq_writer @@ fun () ->
            projection_cpn |> List.map @@ fun pe_cpn ->
              Rocq_writer.rocq_print_small_list_element TranslatorArgs.rocq_writer @@ fun () ->
                decode_place_element pe_cpn
      in
      Ok
        (translate_projection loc (List.rev place_elems)
           (Ast.Var (loc, id))
           local_is_mutable)

    let result_of_outcome loc expr =
      if TranslatorArgs.ignore_unwind_paths then expr
      else
        Ast.CallExpr
          (loc, "fn_outcome_result", [], [], [ LitPat expr ], Static)

    let translate_scalar (s_cpn : D.scalar) (ty : Ast.type_expr) (loc : Ast.loc)
        =
      let open ScalarRd in
      match s_cpn with
      | Int scalar_int_cpn -> translate_scalar_int scalar_int_cpn ty loc
      | Ptr _ ->
          match ty with
          | Ast.RustRefTypeExpr (_, _, Shared, pointee_ty) ->
            let expr = Ast.CallExpr (loc, "std::verifast::produce_const_ref", [pointee_ty], [], [], Static) in
            let expr = result_of_outcome loc expr in
            Ok expr
          | _ -> Ast.static_error loc "TODO: Scalar::Ptr with non-ref type" None

    let mk_unit_expr loc =
      Ast.CastExpr
        ( loc,
          StructTypeExpr (loc, Some TrTyTuple.tuple0_name, None, [], []),
          InitializerList (loc, []) )

    let translate_unit_constant (loc : Ast.loc) = Ok `TrUnitConstant

    let translate_const_value (cv_cpn : D.const_value) (ty_cpn : D.ty)
        (loc : Ast.loc) =
      let open ConstValueRd in
      let* ty_info = translate_decoded_ty ty_cpn loc in
      let ty = ty_info.vf_ty in
      match cv_cpn with
      | Scalar scalar_cpn ->
          let* expr = translate_scalar scalar_cpn ty loc in
          Ok (`TrTypedConstantScalar expr)
      | ZeroSized -> (
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
            Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "ZeroSized"
          end;
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
            Rocq_writer.rocq_print_data TranslatorArgs.rocq_writer Vf_mir_rocq.rocq_print_ty ty_cpn
          end;
          match ty with
          | Ast.ManifestTypeExpr (_, Ast.StructType (sn, _))
            when sn = TrTyTuple.tuple0_name ->
              translate_unit_constant loc
          | _ -> failwith "Todo: ConstValue::ZeroSized")
      | Slice _ -> failwith "Todo: ConstValue::Slice"

    let translate_mir_ty_const (ty_const_cpn : VfMirRd.MirConst.TyData.t)
        (loc : Ast.loc) =
      let open VfMirRd.MirConst.TyData in
      let ty_cpn = ty_get ty_const_cpn in
      let ty = decode_ty (D.decode_ty ty_cpn) in
      match ty with
      | `Tuple [] -> translate_unit_constant loc
      | `FnDef fn_def_ty_cpn -> Ok (`TrTypedConstantFn fn_def_ty_cpn)
      | `Int _ | `Uint _ | `Bool ->
          let const_cpn = const_get ty_const_cpn in
          let* e = translate_ty_const (D.decode_ty_const const_cpn) loc in
          Ok (`TrTypedConstantScalar e)
      | _ -> failwith "Todo: Constant of unsupported type"

    let translate_mir_const (constant_kind_cpn : VfMirRd.MirConst.t)
        (loc : Ast.loc) =
      let open VfMirRd.MirConst in
      match get constant_kind_cpn with
      | Ty ty_const_cpn -> translate_mir_ty_const ty_const_cpn loc
      | Val val_cpn -> (
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Val" @@ fun () ->
          let open VfMirRd.MirConst.Val in
          let ty_cpn = D.decode_ty (ty_get val_cpn) in
          let ty = decode_ty ty_cpn in
          match ty with
          | `FnDef fn_def_ty_cpn ->
              Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
                Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "ZeroSized"
              end;
              Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
                Rocq_writer.rocq_print_data TranslatorArgs.rocq_writer Vf_mir_rocq.rocq_print_ty ty_cpn
              end;
              Ok (`TrTypedConstantFn fn_def_ty_cpn)
          | `Ref (_, _, `Str) -> (
              match ConstValueRd.get @@ const_value_get val_cpn with
              | Slice bytes ->
                  Ok
                    (`TrTypedConstantScalar
                      (Ast.StringLit (loc, bytes)))
              | _ -> failwith "TODO")
          | _ ->
              translate_const_value
                (D.decode_const_value (const_value_get val_cpn))
                ty_cpn loc)
      | Unevaluated _ ->
        let Unevaluated {def; args; ty} = D.decode_mir_const constant_kind_cpn in
        let* args = ListAux.try_map (fun arg -> translate_generic_arg arg loc) args in
        begin match def, args with
          "core::mem::SizedTypeProperties::IS_ZST", [ Mir.GenArgType ty ] ->
          Ok (`TrTypedConstantScalar (Ast.CallExpr (loc, "std::mem::IS_ZST", [ty.Mir.vf_ty], [], [], Static)))
        | "core::mem::SizedTypeProperties::LAYOUT", [ Mir.GenArgType ty ] ->
          Ok (`TrTypedConstantScalar (Ast.CallExpr (loc, "std::alloc::Layout::new", [ty.Mir.vf_ty], [], [], Static)))
        | "core::mem::SizedTypeProperties::MAX_SLICE_LEN", [ Mir.GenArgType ty ] ->
          Ok (`TrTypedConstantScalar (Ast.CallExpr (loc, "std::mem::MAX_SLICE_LEN", [ty.Mir.vf_ty], [], [], Static)))
        | _ ->
          let* ty_info = translate_decoded_ty ty loc in
          let expr = Ast.CallExpr (loc, "std::verifast::unevaluated_constant", [ty_info.vf_ty], [], [], Static) in
          Ok (`TrTypedConstantScalar (result_of_outcome loc expr))
        end
      | Undefined _ -> Error (`TrConstantKind "Unknown ConstantKind")

    let translate_const_operand (constant_cpn : ConstOperandRd.t) =
      let open ConstOperandRd in
      let span_cpn = span_get constant_cpn in
      let* loc = translate_span_data span_cpn in
      let const_cpn = const_get constant_cpn in
      translate_mir_const const_cpn loc

    let translate_operand (operand_cpn : OperandRd.t) (loc : Ast.loc) =
      let open OperandRd in
      (* Todo @Nima: Move and Copy are ignored for now. It is checked by the Rust compiler that
         - Only Places of type Copy get used for Operand::Copy
         - Places used by Operand::Move will never get used again (obviously raw pointers are not tracked)
      *)
      match get operand_cpn with
      | Copy place_cpn ->
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Copy" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
          let* place, place_is_mutable = translate_place place_cpn loc in
          Ok (`TrOperandCopy place)
      | Move place_cpn ->
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Move" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
          let* place, place_is_mutable = translate_place place_cpn loc in
          Ok (`TrOperandMove (place, place_is_mutable))
      | Constant constant_cpn ->
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Constant" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
          translate_const_operand constant_cpn
      | RuntimeChecks checks_cpn ->
          begin match VfMirRd.RuntimeChecks.get checks_cpn with
            UbChecks ->
              let expr = Ast.CallExpr (loc, "std::intrinsics::ub_checks", [], [], [], Static) in
              let expr =
                if TranslatorArgs.ignore_unwind_paths then
                  expr
                else
                  Ast.CallExpr (loc, "fn_outcome_result", [], [], [ LitPat expr ], Static)
              in
              Ok (`TrOperandCopy expr)
          | _ ->
              Ast.static_error loc
                "Nullary operations are not yet supported" None
          end
      | Undefined _ -> Error (`TrOperand "Unknown Mir Operand kind")

    let translate_operands_core (is_variable_length : bool) (oprs : (OperandRd.t * Ast.loc) list) =
      (* We want to preserve Rust's left to right argument evaluation *)
      let tmp_rvalue_binders = ref [] in
      let translate_opr ((opr_cpn, loc) : OperandRd.t * Ast.loc) =
        let* opr = translate_operand opr_cpn loc in
        match opr with
        | `TrOperandCopy operand_expr
        | `TrOperandMove (operand_expr, _ (*place_is_mutable*)) ->
            Ok operand_expr
        | `TrTypedConstantRvalueBinderBuilder rvalue_binder_builder ->
            let tmp_var_cnt = List.length !tmp_rvalue_binders in
            let tmp_var_name =
              TrName.make_tmp_var_name (Int.to_string tmp_var_cnt)
            in
            let rvalue_binder = rvalue_binder_builder tmp_var_name in
            tmp_rvalue_binders := !tmp_rvalue_binders @ [ rvalue_binder ];
            Ok (Ast.Var (loc, tmp_var_name))
        | `TrTypedConstantFn _ ->
            failwith
              "Todo: Functions as operand in rvalues are not supported yet"
        | `TrTypedConstantScalar expr -> Ok expr
      in
      let* oprs =
        if is_variable_length then
          Rocq_writer.rocq_print_small_list TranslatorArgs.rocq_writer @@ fun () ->
          oprs |> ListAux.try_map @@ fun opr ->
            Rocq_writer.rocq_print_small_list_element TranslatorArgs.rocq_writer @@ fun () ->
            translate_opr opr
        else
          ListAux.try_map translate_opr oprs
      in
      Ok (!tmp_rvalue_binders, oprs)

    let translate_operands (oprs : (OperandRd.t * Ast.loc) list) =
      translate_operands_core false oprs
    
    let translate_ghost_generic_arg_list (ggal_cpn : AnnotationRd.t) =
      let* ggal = translate_annotation ggal_cpn in
      let ggal = translate_annot_to_vf_parser_inp ggal in
      Ok (VfMirAnnotParser.parse_ghost_generic_arg_list ggal)

    type fn_call_result =
      | FnCallResult of Ast.expr
      | FnCallOutcome of Ast.expr (* 'returning(result)' or 'unwinding' *)

    let translate_fn_call_rexpr (callee_cpn : OperandRd.t)
        (args_cpn : OperandRd.t list) (call_loc : Ast.loc) (fn_loc : Ast.loc)
        (ghost_generic_arg_list_opt_cpn : OptionRd.t) =
      let has_closure_substs =
        match D.decode_operand callee_cpn with
          Constant {const = Val {ty = {kind = FnDef { id = { name }; substs }}}} ->
            Printf.printf "%s\n" (String.concat ", " (List.map (fun arg -> string_of_generic_arg (decode_generic_arg arg)) substs));
            List.exists
              (fun arg -> match (arg : D.generic_arg) with { kind = Type { kind = Closure _ } } -> true | _ -> false)
              substs
        | _ -> false
      in
      if has_closure_substs then
        Ok
          ( [],
            FnCallResult
              (Ast.CallExpr
                  ( fn_loc,
                    "#verifast_call_with_closure_genargs",
                    [],
                    [],
                    [],
                    Static )) )
      else
      (* Todo @Nima: There should be a way to get separated source spans for args *)
      let args = List.map (fun arg_cpn -> (arg_cpn, fn_loc)) args_cpn in
      let* tmp_rvalue_binders, args =
        Rocq_writer.rocq_print_big_record_field TranslatorArgs.rocq_writer "args" @@ fun () ->
        translate_operands_core true args
      in
      let is_ast_literal_one = function
        | Ast.CastExpr (_, _, Ast.IntLit (_, value, _, _, _))
        | Ast.IntLit (_, value, _, _, _) ->
            Big_int.compare_big_int value Big_int.unit_big_int = 0
        | _ -> false
      in
      let translate_regular_fn_call ?targs_override substs fn_name =
        let inferred_targs =
          substs
          |> Util.flatmap @@ function
             | Mir.GenArgType ty -> [ ty.vf_ty ]
             | Mir.GenArgLifetime region ->
                 [ Ast.InferredTypeExpr call_loc ]
             | Mir.GenArgConst ty -> [ ty ]
        in
        let* targs =
          match targs_override with
          | Some targs -> Ok targs
          | None ->
              (match OptionRd.get ghost_generic_arg_list_opt_cpn with
               | Nothing -> Ok inferred_targs
               | Something ptr_cpn ->
                   let ghost_generic_arg_list_cpn = VfMirRd.of_pointer ptr_cpn in
                   translate_ghost_generic_arg_list ghost_generic_arg_list_cpn)
        in
        let projection_equality =
          let open Ast in
          let callback_referent = function
            | IdentTypeExpr (_, None, name) -> Some (HrtbParam name)
            | ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 3)) ->
                Some HrtbU64
            | _ -> None
          in
          let tuple_shared_referents = function
            | StructTypeExpr
                (_, Some "std_tuple_2_", None, [],
                 [ RustRefTypeExpr (_, lft1, Shared, t1);
                   RustRefTypeExpr (_, lft2, Shared, t2) ]) ->
                (Some lft1, callback_referent t1,
                 Some lft2, callback_referent t2)
            | _ -> (None, None, None, None)
          in
          let source_ref_lifetime_matches source_lft ghost_lft =
            match source_lft, ghost_lft with
            | Some (InferredTypeExpr _), _ -> true
            | Some (IdentTypeExpr (_, None, source_name)),
              IdentTypeExpr (_, None, ghost_name) -> source_name = ghost_name
            | _ -> false
          in
          let callback_type_name = function
            | HrtbParam name -> name
            | HrtbU64 -> "u64"
          in
          match (canonicalize_item_name fn_name, substs, targs) with
          | ( "std::ops::FnMut::call_mut",
              [ Mir.GenArgType { vf_ty = IdentTypeExpr (_, None, source_f); _ };
                Mir.GenArgType { vf_ty = source_args_ty; _ };
                Mir.GenArgLifetime source_method_lft ],
              [ (IdentTypeExpr (_, None, ghost_f) as f_ty);
                (StructTypeExpr (_, Some "std_tuple_2_", None, [],
                   [ RustRefTypeExpr (_, IdentTypeExpr (_, None, lft1), Shared, ghost_t1);
                     RustRefTypeExpr (_, IdentTypeExpr (_, None, lft2), Shared, ghost_t2) ]) as args_ty);
                IdentTypeExpr (_, None, method_lft) ] ) ->
              let source_lft1, source_t1, source_lft2, source_t2 =
                tuple_shared_referents source_args_ty
              in
              let ghost_t1 = callback_referent ghost_t1 in
              let ghost_t2 = callback_referent ghost_t2 in
              let referent =
                match source_t1, source_t2, ghost_t1, ghost_t2 with
                | Some source_t1, Some source_t2, Some ghost_t1, Some ghost_t2
                  when source_t1 = source_t2 && source_t1 = ghost_t1 &&
                       source_t1 = ghost_t2 -> Some source_t1
                | _ -> None
              in
              let explicit_same_lifetime =
                lft1 = lft2 && lft1 = method_lft &&
                String.length lft1 > 0 && lft1.[0] = '\''
              in
              let source_lifetimes_match =
                source_ref_lifetime_matches source_lft1
                  (IdentTypeExpr (call_loc, None, lft1)) &&
                source_ref_lifetime_matches source_lft2
                  (IdentTypeExpr (call_loc, None, lft2))
              in
              (match referent with
               | Some referent
                 when source_f = ghost_f && explicit_same_lifetime &&
                      source_lifetimes_match &&
                      source_method_lft = "'erased" &&
                      List.filter
                        (fun (f, t) -> f = source_f && t = referent)
                        !State.hrtb_fnmut_output_bounds
                      = [ (source_f, referent) ] ->
                   Printf.eprintf
                     "MERGE_HRTB_CALL registered=1 function=%s F=%s T=%s lifetime=%s call=%s\n%!"
                     (canonicalize_item_name fn_name) source_f
                     (callback_type_name referent) lft1
                     (Ast.string_of_loc call_loc);
                   [ ExprStmt
                       (CallExpr
                          ( call_loc, "#register_type_projection_equality",
                            [ ProjectionTypeExpr
                                (call_loc, f_ty, "std::ops::FnOnce", [ args_ty ], "Output");
                              ManifestTypeExpr (call_loc, Bool) ],
                            [], [], Static )) ]
               | _ ->
                   Printf.eprintf
                     "MERGE_HRTB_CALL registered=0 function=%s source_substs=%d ghost_substs=%d eligible_bounds=%d call=%s\n%!"
                     (canonicalize_item_name fn_name) (List.length substs)
                     (List.length targs) (List.length !State.hrtb_fnmut_output_bounds)
                     (Ast.string_of_loc call_loc);
                   [])
          | _ ->
              if canonicalize_item_name fn_name = "std::ops::FnMut::call_mut" then
                Printf.eprintf
                  "MERGE_HRTB_CALL registered=0 function=%s source_substs=%d ghost_substs=%d eligible_bounds=%d call=%s\n%!"
                  (canonicalize_item_name fn_name) (List.length substs)
                  (List.length targs) (List.length !State.hrtb_fnmut_output_bounds)
                  (Ast.string_of_loc call_loc);
              []
        in
        State.pending_hrtb_projection_eq := projection_equality;
        let args = List.map (fun expr -> Ast.LitPat expr) args in
        let call_expr =
          Ast.CallExpr
            ( call_loc,
              fn_name,
              targs (*type arguments*),
              [] (*indices, in case this is really a predicate assertion*),
              args,
              Ast.Static (*method_binding*) )
        in
        Ok (tmp_rvalue_binders, FnCallOutcome call_expr)
      in
      let* callee =
        Rocq_writer.rocq_print_big_record_field TranslatorArgs.rocq_writer "func" @@ fun () ->
        translate_operand callee_cpn call_loc
      in
      match callee with
      | `TrOperandMove (Var (_, fn_name), place_is_mutable) ->
          translate_regular_fn_call [] fn_name
      | `TrTypedConstantFn fn_def_ty_cpn -> (
          let fn_name = fn_def_ty_cpn.id.name in
          let substs_cpn = fn_def_ty_cpn.substs in
          if State.is_generated_glue then begin
            let binding = match State.generated_glue with
              | Some binding -> binding
              | None -> Ast.static_error call_loc "Unbound generated Drop glue" None in
            let raw_trait = canonicalize_item_name fn_name in
            let expected_trait = canonicalize_item_name binding.glue_raw_trait_path in
            let concrete_guard = match substs_cpn with
              | [{ D.kind = D.Type ty }] ->
                  (match decode_ty ty with
                   | `Adt (guard, _, []) -> Some guard
                   | _ -> None)
              | _ -> None in
            if raw_trait <> expected_trait ||
               concrete_guard <> Some binding.glue_guard ||
               fn_def_ty_cpn.late_bound_generic_param_count <> 1 ||
               List.length args_cpn <> 1 || tmp_rvalue_binders <> [] ||
               (match args with [Ast.Var _] -> false | _ -> true) then
              Ast.static_error call_loc
                "Generated Drop trait call differs from the resolved local instance" None;
            Ok ([], FnCallOutcome
              (Ast.CallExpr (fn_loc, binding.glue_selected_path,
                 [Ast.InferredTypeExpr call_loc], [],
                 [Ast.LitPat (List.hd args)], Ast.Static)))
          end else
          let fn_name = translate_fn_name fn_name substs_cpn in
          let substs_cpn =
            substs_cpn
            @ List.init fn_def_ty_cpn.late_bound_generic_param_count
                (fun i : D.generic_arg ->
                  { kind = Lifetime { id = "'erased"; identity = Nothing } })
          in
          let fn_name, substs_cpn =
            Args.body_tr_defs_ctx.fn_specializer fn_name substs_cpn
          in
          let* substs =
            ListAux.try_map
              (fun arg -> translate_generic_arg arg call_loc)
              substs_cpn
          in
          if substs = [] then translate_regular_fn_call [] fn_name
          else
            match fn_name with
            (* Todo @Nima: For cases where we inline an expression instead of a function call,
               there is a problem with extending the implementation for clean-up paths *)
            | "VeriFast_alloc" ->
                let [ Mir.GenArgType ty_info ] = substs in
                Ok
                  ( [],
                    FnCallResult
                      (Ast.CallExpr
                         ( fn_loc,
                           "malloc",
                           [],
                           [],
                           [ LitPat (SizeofExpr (fn_loc, TypeExpr ty_info.vf_ty)) ],
                           Static )) )
            | "VF_free" ->
                let [ Mir.GenArgType ty_info ] = substs in
                let [ arg ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult
                      (Ast.CallExpr
                         ( fn_loc,
                           "std::alloc::VeriFast_dealloc",
                           [],
                           [],
                           [ LitPat (CastExpr (fn_loc, PtrTypeExpr (fn_loc, ty_info.vf_ty), arg)) ],
                           Static )) )
            | "std::ptr::mut_ptr::<impl *mut T>::is_null" -> (
                match (substs, args_cpn) with
                | [ Mir.GenArgType gen_arg_ty_info ], [ arg_cpn ] ->
                    let [ arg ] = args in
                    Ok
                      ( tmp_rvalue_binders,
                        FnCallResult
                          (Ast.Operation
                             ( fn_loc,
                               Ast.Eq,
                               [
                                 arg;
                                 IntLit
                                   ( fn_loc,
                                     Big_int.zero_big_int,
                                     (*decimal*) true,
                                     (*U suffix*) false,
                                     (*int literal*) Ast.NoLSuffix );
                               ] )) )
                | _ ->
                    Error
                      (`TrFnCallRExpr
                        "Invalid (generic) arg(s) for std::ptr::mut_ptr::<impl \
                         *mut T>::is_null"))
            | "std::ptr::mut_ptr::<impl *const T>::cast"
            | "std::ptr::mut_ptr::<impl *mut T>::cast" ->
                let [ _; Mir.GenArgType gen_arg_ty_info ], [ arg_cpn ] =
                  (substs, args_cpn)
                in
                let [ arg ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult
                      (Ast.CastExpr
                         ( fn_loc,
                           PtrTypeExpr (fn_loc, gen_arg_ty_info.vf_ty),
                           arg )) )
            (* `p.cast_slice(n)` is defined as `slice_from_raw_parts_mut(p, n)`. *)
            | "std::ptr::const_ptr::<impl *const T>::cast_slice"
            | "std::ptr::mut_ptr::<impl *mut T>::cast_slice" ->
                let [ Mir.GenArgType gen_arg_ty_info ] = substs in
                let [ arg1; arg2 ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult
                      (Ast.CallExpr
                         ( fn_loc,
                           "std::ptr::slice_from_raw_parts_mut",
                           [ gen_arg_ty_info.vf_ty ],
                           [],
                           [ LitPat arg1; LitPat arg2 ],
                           Static )) )
            | "std::ptr::const_ptr::<impl *const T>::offset"
            | "std::ptr::mut_ptr::<impl *mut T>::offset" -> (
                match (substs, args_cpn) with
                | [ Mir.GenArgType gen_arg_ty_info ], [ arg1_cpn; arg2_cpn ] ->
                    let [ arg1; arg2 ] = args in
                    Ok
                      ( tmp_rvalue_binders,
                        FnCallResult
                          (Ast.Operation (fn_loc, Ast.Add, [ arg1; arg2 ])) )
                | _ ->
                    Error
                      (`TrFnCallRExpr
                        (Printf.sprintf "Invalid (generic) arg(s) for %s"
                           fn_name)))
            | "std::ptr::const_ptr::<impl *const T>::offset_from"
            | "std::ptr::mut_ptr::<impl *mut T>::offset_from" -> (
                match (substs, args_cpn) with
                | [ Mir.GenArgType gen_arg_ty_info ], [ arg1_cpn; arg2_cpn ] ->
                    let [ arg1; arg2 ] = args in
                    Ok
                      ( tmp_rvalue_binders,
                        FnCallOutcome
                          (Ast.CallExpr
                             ( fn_loc,
                               "std::intrinsics::ptr_offset_from",
                               [ gen_arg_ty_info.vf_ty ],
                               [],
                               [ LitPat arg1; LitPat arg2 ],
                               Static )) )
                | _ ->
                    Error
                      (`TrFnCallRExpr
                        (Printf.sprintf "Invalid (generic) arg(s) for %s"
                           fn_name)))
            (* Keep wrapping arithmetic separate from the ordinary Add/Sub
               pointer operations.  The target functions have bounded
               preconditions and a modular, provenance-preserving post. *)
            | "std::ptr::const_ptr::<impl *const T>::wrapping_add"
            | "std::ptr::const_ptr::<impl *const T>::wrapping_sub"
            | "std::ptr::const_ptr::<impl *const T>::wrapping_offset"
            | "std::ptr::mut_ptr::<impl *mut T>::wrapping_add"
            | "std::ptr::mut_ptr::<impl *mut T>::wrapping_sub"
            | "std::ptr::mut_ptr::<impl *mut T>::wrapping_offset" -> (
                match (substs, args_cpn) with
                | [ Mir.GenArgType gen_arg_ty_info ], [ _; _ ] ->
                    let [ ptr; count ] = args in
                    let primitive_name =
                      match fn_name with
                      | "std::ptr::const_ptr::<impl *const T>::wrapping_add" ->
                          "std::intrinsics::verifast_wrapping_add_const"
                      | "std::ptr::const_ptr::<impl *const T>::wrapping_sub" ->
                          "std::intrinsics::verifast_wrapping_sub_const"
                      | "std::ptr::const_ptr::<impl *const T>::wrapping_offset" ->
                          "std::intrinsics::verifast_wrapping_offset_const"
                      | "std::ptr::mut_ptr::<impl *mut T>::wrapping_add" ->
                          "std::intrinsics::verifast_wrapping_add_mut"
                      | "std::ptr::mut_ptr::<impl *mut T>::wrapping_sub" ->
                          "std::intrinsics::verifast_wrapping_sub_mut"
                      | "std::ptr::mut_ptr::<impl *mut T>::wrapping_offset" ->
                          "std::intrinsics::verifast_wrapping_offset_mut"
                      | _ -> assert false
                    in
                    Ok
                      ( tmp_rvalue_binders,
                        FnCallOutcome
                          (Ast.CallExpr
                             ( fn_loc,
                               primitive_name,
                               [ gen_arg_ty_info.vf_ty ],
                               [],
                               [ LitPat ptr; LitPat count ],
                               Static )) )
                | _ ->
                    Error
                      (`TrFnCallRExpr
                        (Printf.sprintf "Invalid (generic) arg(s) for %s"
                           fn_name)))
            | "std::ptr::const_ptr::<impl *const T>::add"
            | "std::ptr::mut_ptr::<impl *mut T>::add" -> (
                match (substs, args_cpn) with
                | [ Mir.GenArgType gen_arg_ty_info ], [ arg1_cpn; arg2_cpn ] ->
                    let [ arg1; arg2 ] = args in
                    Ok
                      ( tmp_rvalue_binders,
                        FnCallResult
                          (Ast.Operation
                             ( fn_loc,
                               Ast.Add,
                               [
                                 arg1;
                                 arg2
                               ] )) )
                | _ ->
                    Error
                      (`TrFnCallRExpr
                        (Printf.sprintf "Invalid (generic) arg(s) for %s"
                           fn_name)))
            | "std::ptr::const_ptr::<impl *const T>::sub"
            | "std::ptr::mut_ptr::<impl *mut T>::sub" -> (
                match (substs, args_cpn) with
                | [ Mir.GenArgType gen_arg_ty_info ], [ arg1_cpn; arg2_cpn ] ->
                    let [ arg1; arg2 ] = args in
                    Ok
                      ( tmp_rvalue_binders,
                        FnCallResult
                          (Ast.Operation
                             ( fn_loc,
                               Ast.Sub,
                               [
                                 arg1;
                                 CastExpr
                                   ( fn_loc,
                                     ManifestTypeExpr
                                       (fn_loc, Int (Signed, PtrRank)),
                                     arg2 );
                               ] )) )
                | _ ->
                    Error
                      (`TrFnCallRExpr
                        (Printf.sprintf "Invalid (generic) arg(s) for %s"
                           fn_name)))
            | "std::ptr::null_mut" ->
                Ok
                  ( [],
                    FnCallResult
                      (IntLit
                         ( fn_loc,
                           Big_int.zero_big_int,
                           (*decimal*) true,
                           (*U suffix*) false,
                           (*int literal*) Ast.NoLSuffix )) )
            | "std::ptr::copy_nonoverlapping"
              when (match args with
                    | [ _src; _dst; count ] -> is_ast_literal_one count
                    | _ -> false) ->
                translate_regular_fn_call substs
                  "std::ptr::merge_copy_nonoverlapping_one"
            | "std::ptr::read" | "std::ptr::mut_ptr::<impl *mut T>::read"
            | "std::ptr::const_ptr::<impl *const T>::read" ->
                let [ src_cpn ] = args_cpn in
                let [ src ] = args in
                Ok (tmp_rvalue_binders, FnCallResult (Ast.Deref (fn_loc, src)))
            | "std::ptr::write" | "std::ptr::mut_ptr::<impl *mut T>::write" ->
                let [ dst_cpn; src_cpn ] = args_cpn in
                let [ dst; src ] = args in
                Ok
                  ( tmp_rvalue_binders
                    @ [
                        Ast.ExprStmt
                          (AssignExpr
                             (fn_loc, Deref (fn_loc, dst), Mutation, src));
                      ],
                    FnCallResult (mk_unit_expr fn_loc) )
            | "std::cell::UnsafeCell::<T>::new"
            | "std::mem::ManuallyDrop::<T>::new"
            | "std::mem::ManuallyDrop::deref"
            | "std::mem::ManuallyDrop::deref_mut" ->
                let [ arg_cpn ] = args_cpn in
                let [ arg ] = args in
                Ok (tmp_rvalue_binders, FnCallResult arg)
            | "std::cell::UnsafeCell::<T>::get" ->
                let [ arg_cpn ] = args_cpn in
                let [ arg ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult
                      (CallExpr
                         (fn_loc, "ref_origin", [], [], [ LitPat arg ], Static))
                  )
            | "std::cell::UnsafeCell::<T>::into_inner" ->
                let [ arg ] = args in Ok (tmp_rvalue_binders, FnCallResult arg)
            | "std::str::<impl str>::as_ptr" | "std::str::<impl str>::as_mut_ptr" ->
                let [ arg_cpn ] = args_cpn in
                let [ arg ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult (CastExpr (fn_loc, PtrTypeExpr (fn_loc, ManifestTypeExpr (fn_loc, Int (Unsigned, FixedWidthRank 0))), arg)) )
            | "std::slice::<impl [T]>::as_ptr" ->
                let [ Mir.GenArgType gen_arg_ty_info; _ ] = substs in
                let [ arg ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult (Ast.CastExpr (fn_loc, PtrTypeExpr (fn_loc, gen_arg_ty_info.vf_ty), arg)) )
            | "std::slice::<impl [T]>::as_mut_ptr" ->
                (match State.r23_source_array_adapter,
                       substs, args, args_cpn with
                 | Some plan,
                   [Mir.GenArgType gen_arg_ty_info; _], [arg], [arg_cpn] ->
                     let receiver_id = match OperandRd.get arg_cpn with
                       | OperandRd.Copy place | OperandRd.Move place
                         when PlaceRd.projection_get_list place = [] ->
                           Some (LocalDeclIdRd.name_get
                             (PlaceRd.local_get place))
                       | _ -> None in
                     let is_u64 = match gen_arg_ty_info.vf_ty with
                       | Ast.ManifestTypeExpr (_, Ast.Int
                           (Ast.Unsigned, Ast.FixedWidthRank 3)) -> true
                       | _ -> false in
                     if receiver_id <> plan.r23_unsize_local ||
                        not plan.r23_ref_seen || not plan.r23_unsize_seen ||
                        plan.r23_call_seen || not is_u64 ||
                        not plan.r23_projection_approved
                     then
                       Ast.static_error fn_loc
                         "R23 as_mut_ptr receiver/type/use differs from the admitted Ref-Unsize chain or checked callee projection"
                         None;
                     let helper_name = match plan.r23_checked_helper_name with
                       | Some name -> name
                       | None -> Ast.static_error fn_loc
                           "R23 checked helper name is absent after projection admission"
                           None in
                     plan.r23_call_seen <- true;
                     let k = Ast.Var (fn_loc, plan.r23_lifetime_token) in
                     let t = Ast.Var (fn_loc, "t") in
                     let p = Ast.Var (fn_loc, "r23_array_p") in
                     let slice_raw_ty = Ast.PtrTypeExpr
                       (fn_loc, Ast.SliceTypeExpr (fn_loc, gen_arg_ty_info.vf_ty)) in
                     let slice_raw = Ast.CastExpr (fn_loc, slice_raw_ty, arg) in
                     let pre_bridge = Ast.ExprStmt
                       (Ast.CallExpr
                          (fn_loc, "r23_array3_borrow_to_slice", [], [],
                           [ Ast.LitPat k; Ast.LitPat t; Ast.LitPat p;
                             Ast.LitPat slice_raw ], Ast.Static)) in
                     let post_bridge = Ast.ExprStmt
                       (Ast.CallExpr
                          (fn_loc, "r23_slice_borrow_to_array3", [], [],
                           [ Ast.LitPat k; Ast.LitPat t; Ast.LitPat p;
                             Ast.LitPat slice_raw ], Ast.Static)) in
                     State.r23_adapter_post_bridge := Some post_bridge;
                     let* _, helper_call = translate_regular_fn_call
                       ~targs_override:
                         [Ast.IdentTypeExpr (fn_loc, None, "'r23_borrow")]
                       [] helper_name in
                     (* The helper is emitted from the paired source body and
                        independently checked against the actual std callee
                        projection during admission. Its verified contract
                        retains the borrow and its body computes the data
                        pointer. *)
                     (match helper_call with
                      | FnCallOutcome _ ->
                          Ok (tmp_rvalue_binders @ [pre_bridge], helper_call)
                      | FnCallResult _ -> Ast.static_error fn_loc
                          "R23 checked helper call did not preserve its outcome"
                          None)
                 | None, _, _, _ -> translate_regular_fn_call substs fn_name
                 | _ ->
                     Ast.static_error fn_loc
                       "R23 source adapter as_mut_ptr call shape changed after body admission"
                       None)
            | "std::str::<impl str>::len" | "std::slice::<impl [T]>::len" | "std::ptr::const_ptr::<impl *const [T]>::len" | "std::ptr::mut_ptr::<impl *mut [T]>::len" ->
                let [ arg ] = args in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult (CallExpr (fn_loc, "ptr_len", [], [], [LitPat arg], Static)) )
            | "std::str::<impl str>::as_bytes" ->
                let [ arg ] = args in
                let slice_u8_ref_ty =
                  Ast.RustRefTypeExpr
                    ( fn_loc,
                      ManifestTypeExpr (fn_loc, StaticLifetime),
                      Shared,
                      SliceTypeExpr
                        ( fn_loc,
                           ManifestTypeExpr
                             (fn_loc, Int (Unsigned, FixedWidthRank 0))))
                in
                Ok
                  ( tmp_rvalue_binders,
                    FnCallResult
                      (Ast.CastExpr
                         ( fn_loc,
                           slice_u8_ref_ty,
                           arg )) )
            | _ -> translate_regular_fn_call substs fn_name)
      | _ ->
          Error (`TrFnCallRExpr "Invalid function definition type translation")

    let translate_unwind_action (unwind_action_cpn : UnwindActionRd.t)
        (loc : Ast.loc) =
      let open UnwindActionRd in
      match get unwind_action_cpn with
      | Continue ->
          ( [
              Ast.ReturnStmt
                ((if State.is_generated_glue then Ast.DummyLoc else loc),
                 Some (Ast.CallExpr (loc, "unwinding", [], [], [], Static)));
            ],
            [] )
      | Unreachable -> ([ Ast.Assert (loc, Ast.False loc) ], [])
      | Terminate ->
          ( [
              Ast.ExprStmt
                (CallExpr (loc, "std::process::abort", [], [], [], Static));
            ],
            [] )
      | Cleanup bblock_id_cpn ->
          let bblock_id = translate_basic_block_id bblock_id_cpn in
          ([ Ast.GotoStmt (loc, bblock_id) ], [ bblock_id ])

    let translate_fn_call (fn_call_data_cpn : FnCallDataRd.t) (loc : Ast.loc) =
      let open FnCallDataRd in
      State.pending_hrtb_projection_eq := [];
      Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Call" @@ fun () ->
      Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
      Rocq_writer.rocq_print_big_record TranslatorArgs.rocq_writer @@ fun () ->
      let func_cpn = func_get fn_call_data_cpn in
      let fn_span_cpn = call_span_get fn_call_data_cpn in
      let* fn_loc = translate_span_data fn_span_cpn in
      let args_cpn = args_get_list fn_call_data_cpn in
      let ghost_generic_arg_list_opt_cpn =
        ghost_generic_arg_list_get fn_call_data_cpn
      in
      let* fn_call_tmp_rval_ctx, fn_call_rexpr =
        translate_fn_call_rexpr func_cpn args_cpn loc fn_loc
          ghost_generic_arg_list_opt_cpn
      in
      (match State.callback_scope_start, State.callback_close, fn_call_rexpr with
       | Some start, Some (close_loc, _, _),
         (FnCallOutcome (Ast.CallExpr (_, name, _, _, _, _)) |
          FnCallResult (Ast.CallExpr (_, name, _, _, _, _))) ->
           let pos l = fst (Ast.lexed_loc l) in
           if pos start < pos loc && pos loc < pos close_loc &&
              canonicalize_item_name name <> "std::ops::FnMut::call_mut" &&
              name <> "VeriFast_ghost_command" then
             Ast.static_error loc "Unsupported call inside callback lifetime scope" None
       | _ -> ());
      (match State.callback_close, fn_call_rexpr with
       | Some _, FnCallOutcome (Ast.CallExpr (_, name, _, _, _, _))
         when canonicalize_item_name name = "std::ops::FnMut::call_mut" ->
           incr State.fnmut_call_count
       | _ -> ());
      let unwind_stmts, unwind_targets =
        if TranslatorArgs.ignore_unwind_paths then ([], [])
        else translate_unwind_action (unwind_action_get fn_call_data_cpn) loc
      in
      let first_callback_cleanup =
        match State.first_callback, fn_call_rexpr with
        | Some plan,
          FnCallOutcome (Ast.CallExpr (_, name, targs, [], args, Ast.Static))
          when canonicalize_item_name name = "std::ops::FnMut::call_mut" ->
            let unwind_kind =
              match UnwindActionRd.get (unwind_action_get fn_call_data_cpn) with
              | UnwindActionRd.Continue -> `Continue
              | UnwindActionRd.Cleanup _ -> `Cleanup
              | _ -> `Other
            in
            State.first_fnmut_calls := (loc, unwind_kind) :: !State.first_fnmut_calls;
            let (_, call_end_line, _) = snd (Ast.lexed_loc loc) in
            let ((_, close_line, _), _) = Ast.lexed_loc plan.first_close_loc in
            if close_line = call_end_line + 1 then (
              let u64 = function
                | Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3)) -> true
                | _ -> false
              in
              let typed_call =
                match targs, args with
                | [Ast.IdentTypeExpr (_, None, "F");
                   Ast.StructTypeExpr (_, Some "std_tuple_2_", None, [],
                     [Ast.RustRefTypeExpr (_, Ast.IdentTypeExpr (_, None, lft1),
                        Ast.Shared, t1);
                      Ast.RustRefTypeExpr (_, Ast.IdentTypeExpr (_, None, lft2),
                        Ast.Shared, t2)]);
                   Ast.IdentTypeExpr (_, None, lft3)],
                  [Ast.LitPat (Ast.Var _); Ast.LitPat (Ast.Var _)] ->
                    lft1 = plan.first_lft && lft2 = plan.first_lft &&
                    lft3 = plan.first_lft && u64 t1 && u64 t2
                | _ -> false
              in
              let ((call_file, _, _), _) = Ast.lexed_loc loc in
              if !State.first_callback_used || not typed_call ||
                 !State.pending_hrtb_projection_eq = [] ||
                 (let ((marker_file, _, _), _) =
                    Ast.lexed_loc plan.first_close_loc in
                  call_file <> marker_file) ||
                 TranslatorArgs.ignore_unwind_paths ||
                 (match OptionRd.get (target_get fn_call_data_cpn) with
                  | Something _ -> false | _ -> true) ||
                 unwind_kind <> `Continue ||
                 (match unwind_stmts with
                  | [Ast.ReturnStmt (_, Some (Ast.CallExpr (_, "unwinding", [], [], [], Ast.Static)))] -> false
                  | _ -> true) then
                Ast.static_error loc
                  "First callback recovery requires the typed source FnMut Continue call"
                  None;
              State.first_callback_used := true;
              State.first_callback_call_loc := Some loc;
              Some plan.first_close_stmt)
            else None
        | _ -> None
      in
      let callback_cleanup =
        match State.callback_close, fn_call_rexpr with
        | Some (close_loc, lft, close_stmt),
          FnCallOutcome (Ast.CallExpr (_, name, targs, [], args, Ast.Static))
          when canonicalize_item_name name = "std::ops::FnMut::call_mut" ->
            let typed_call =
              match targs, args with
              | [Ast.IdentTypeExpr (_, None, "F");
                 Ast.StructTypeExpr (_, Some "std_tuple_2_", None, [],
                   [Ast.RustRefTypeExpr (_, Ast.IdentTypeExpr (_, None, lft1),
                      Ast.Shared, Ast.IdentTypeExpr (_, None, "T"));
                    Ast.RustRefTypeExpr (_, Ast.IdentTypeExpr (_, None, lft2),
                      Ast.Shared, Ast.IdentTypeExpr (_, None, "T"))]);
                 Ast.IdentTypeExpr (_, None, lft3)],
                [Ast.LitPat (Ast.Var _); Ast.LitPat (Ast.Var _)] ->
                  lft1 = lft && lft2 = lft && lft3 = lft
              | _ -> false
            in
            let (_, call_end_line, _) = snd (Ast.lexed_loc loc) in
            let ((_, close_line, _), _) = Ast.lexed_loc close_loc in
            if close_line = call_end_line + 1 then (
              if !State.callback_used || not typed_call ||
                 !State.pending_hrtb_projection_eq = [] ||
                 TranslatorArgs.ignore_unwind_paths ||
                 (match OptionRd.get (target_get fn_call_data_cpn) with
                  | Something _ -> false | _ -> true) ||
                 (match UnwindActionRd.get (unwind_action_get fn_call_data_cpn) with
                  | UnwindActionRd.Continue -> false | _ -> true) ||
                 (match unwind_stmts with
                  | [Ast.ReturnStmt (_, Some (Ast.CallExpr (_, "unwinding", [], [], [], Ast.Static)))] -> false
                  | _ -> true) then
                Ast.static_error loc "Callback cleanup requires one typed FnMut call with unwind continue" None;
              State.callback_used := true;
              State.callback_call_loc := Some loc;
              Some close_stmt)
            else None
        | _ -> None
      in
      let late_callback_cleanup =
        match State.late_callback, fn_call_rexpr with
        | Some plan,
          FnCallOutcome (Ast.CallExpr (_, name, targs, [], args, Ast.Static))
          when canonicalize_item_name name = "std::ops::FnMut::call_mut" ->
            let u64 = function
              | Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3)) -> true
              | _ -> false in
            let typed_call =
              match targs, args with
              | [Ast.IdentTypeExpr (_, None, "F");
                 Ast.StructTypeExpr (_, Some "std_tuple_2_", None, [],
                   [Ast.RustRefTypeExpr (_, Ast.IdentTypeExpr (_, None, lft1),
                      Ast.Shared, t1);
                    Ast.RustRefTypeExpr (_, Ast.IdentTypeExpr (_, None, lft2),
                      Ast.Shared, t2)]);
                 Ast.IdentTypeExpr (_, None, lft3)],
                [Ast.LitPat (Ast.Var _); Ast.LitPat (Ast.Var _)] ->
                  lft1 = plan.late_lft && lft2 = plan.late_lft &&
                  lft3 = plan.late_lft && u64 t1 && u64 t2
              | _ -> false in
            let (call_file, call_end_line, _) = snd (Ast.lexed_loc loc) in
            let ((_, close_line, _), _) = Ast.lexed_loc plan.late_close_loc in
            let cleanup_id =
              match UnwindActionRd.get (unwind_action_get fn_call_data_cpn) with
              | UnwindActionRd.Cleanup target ->
                  Some (translate_basic_block_id target)
              | _ -> None in
            if close_line <> call_end_line + 1 then None
            else (
              if !State.late_callback_used || not typed_call ||
                 !State.pending_hrtb_projection_eq = [] ||
                 (let ((scope_file, _, _), _) =
                    Ast.lexed_loc plan.late_begin_loc in
                  call_file <> scope_file) ||
                 TranslatorArgs.ignore_unwind_paths ||
                 (match OptionRd.get (target_get fn_call_data_cpn) with
                  | Something _ -> false | _ -> true) ||
                 cleanup_id = None ||
                 (match unwind_stmts, cleanup_id with
                  | [Ast.GotoStmt (_, target)], Some cleanup -> target <> cleanup
                  | _ -> false) then
                Ast.static_error loc
                  "Late callback recovery requires the typed source FnMut Cleanup call"
                  None;
              State.late_callback_used := true;
              Some (plan, Option.get cleanup_id))
        | _ -> None
      in
      (match late_callback_cleanup, first_callback_cleanup, callback_cleanup with
       | Some _, Some _, _ | Some _, _, Some _ ->
           Ast.static_error loc "Overlapping callback recovery markers" None
       | _ -> ());
      (* R19: the marked block after insert_tail also runs on unwind. *)
      let r19_unwind_cleanup =
        match State.r19_unwind_cleanup, fn_call_rexpr with
        | Some (marker_loc, stmt),
          (FnCallOutcome (Ast.CallExpr (_, name, _, _, _, _)) |
           FnCallResult (Ast.CallExpr (_, name, _, _, _, _)))
          when name = "insert_tail" || String.ends_with ~suffix:"::insert_tail" name ->
            let (call_file, call_end_line, _) = snd (Ast.lexed_loc loc) in
            let ((marker_file, marker_line, _), _) = Ast.lexed_loc marker_loc in
            if marker_line <> call_end_line + 1 || marker_file <> call_file then None
            else (
              if !State.r19_unwind_cleanup_used ||
                 TranslatorArgs.ignore_unwind_paths ||
                 late_callback_cleanup <> None || first_callback_cleanup <> None ||
                 callback_cleanup <> None ||
                 (match fn_call_rexpr with FnCallOutcome _ -> false | _ -> true) ||
                 (match OptionRd.get (target_get fn_call_data_cpn) with
                  | Something _ -> false | _ -> true) ||
                 (match UnwindActionRd.get (unwind_action_get fn_call_data_cpn) with
                  | UnwindActionRd.Continue -> false | _ -> true) ||
                 (match unwind_stmts with
                  | [Ast.ReturnStmt (_, Some (Ast.CallExpr (_, "unwinding", [], [], [], Ast.Static)))] -> false
                  | _ -> true) then
                Ast.static_error loc
                  "R19 cleanup needs a Continue insert_tail call"
                  None;
              State.r19_unwind_cleanup_used := true;
              Some stmt)
        | _ -> None
      in
      let* dst, dst_is_mutable =
        Rocq_writer.rocq_print_big_record_field TranslatorArgs.rocq_writer "destination" @@ fun () ->
        translate_place (destination_get fn_call_data_cpn) loc
      in
      let* call_stmts, terminator, targets =
        Rocq_writer.rocq_print_big_record_field TranslatorArgs.rocq_writer "target" @@ fun () ->
        match OptionRd.get (target_get fn_call_data_cpn) with
        | Nothing ->
            Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "None";
            (*Diverging call*)
            let call_expr =
              match fn_call_rexpr with
              | FnCallResult e -> e
              | FnCallOutcome e -> e
            in
            Ok
              ( [ Ast.ExprStmt call_expr ] @ unwind_stmts,
                Mir.EncodedTerminator,
                [] )
        | Something ptr_cpn ->
            let target_cpn = VfMirRd.of_pointer ptr_cpn in
            let dst_bblock_id = translate_basic_block_id target_cpn in
            (match late_callback_cleanup with
             | Some (_, cleanup_id) ->
                 State.late_callback_call := Some (loc, dst_bblock_id, cleanup_id)
             | None -> ());
            Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Some" begin fun () ->
              Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
                Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer dst_bblock_id
              end
            end;
            let assignment e =
              Ast.ExprStmt
                (Ast.AssignExpr
                   ( loc,
                     dst,
                     (if dst_is_mutable then Mutation else Initialization),
                     e ))
            in
            let assignment_with_r23_recovery e =
              match !(State.r23_adapter_post_bridge) with
              | None -> assignment e
              | Some recover ->
                  Ast.BlockStmt
                    (loc, [], [assignment e; recover], loc, ref [])
            in
            let call_stmt =
              match fn_call_rexpr with
              | FnCallResult e -> assignment_with_r23_recovery e
              | FnCallOutcome e ->
                  if TranslatorArgs.ignore_unwind_paths then assignment e
                  else
                    Ast.SwitchStmt
                      ( loc,
                        e,
                        [
                          Ast.SwitchStmtClause
                            ( loc,
                              CallExpr
                                ( loc,
                                  "returning",
                                  [],
                                  [],
                                  [ LitPat (Var (loc, "__result")) ],
                                  Static ),
                              [ assignment (Ast.Var (loc, "__result")) ] @
                              (match !(State.r23_adapter_post_bridge) with
                               | Some recover -> [recover]
                               | None -> []) @
                              (match late_callback_cleanup,
                                     first_callback_cleanup, callback_cleanup with
                               | Some (plan, _), None, None ->
                                   [Ast.ExprStmt
                                      (Ast.AssignExpr
                                        (loc, Ast.Var (loc, "__vf_late_callback_unwind"),
                                         Ast.Mutation, Ast.False loc));
                                    fresh_first_callback_stmt plan.late_close_stmt]
                               | None, Some s, None | None, None, Some s ->
                                   [fresh_first_callback_stmt s]
                               | None, None, None -> []
                               | Some _, _, _ | _, Some _, Some _ ->
                                   Ast.static_error loc "Overlapping callback recovery markers" None) );
                          Ast.SwitchStmtClause
                            ( loc,
                              CallExpr (loc, "unwinding", [], [], [], Static),
                              (match State.r23_source_array_adapter with
                               | Some plan ->
                                   let recover = match !(State.r23_adapter_post_bridge) with
                                     | Some recover -> recover
                                     | None -> Ast.static_error loc
                                         "R23 slice recovery bridge is missing on unwind"
                                         None in
                                   if plan.r23_unwind_epilogue <> None then
                                     Ast.static_error loc
                                       "R23 source adapter generated more than one unwind epilogue"
                                       None;
                                   let array_to_array = Ast.ExprStmt (Ast.CallExpr
                                     (loc, "array_to_array_", [], [],
                                      [Ast.LitPat (Ast.CastExpr
                                        (loc,
                                         Ast.PtrTypeExpr
                                           (loc, Ast.ManifestTypeExpr
                                             (loc, Ast.Int
                                               (Ast.Unsigned, Ast.FixedWidthRank 3))),
                                         Ast.Var (loc, "r23_array_p")))], Ast.Static)) in
                                   plan.r23_unwind_epilogue <- Some (
                                     [Ast.Assert (loc, Ast.False loc);
                                      Ast.LabelStmt (loc, plan.r23_unwind_label);
                                      fresh_first_callback_stmt plan.r23_post_stmt;
                                      array_to_array] @ unwind_stmts);
                                   [recover; Ast.GotoStmt (loc, plan.r23_unwind_label)]
                               | None ->
                              (match late_callback_cleanup,
                                     first_callback_cleanup, callback_cleanup with
                               | Some (plan, _), None, None ->
                                   [Ast.ExprStmt
                                      (Ast.AssignExpr
                                        (loc, Ast.Var (loc, "__vf_late_callback_unwind"),
                                         Ast.Mutation, Ast.True loc));
                                    fresh_first_callback_stmt plan.late_close_stmt]
                               | None, Some s, None ->
                                   [fresh_first_callback_stmt s;
                                    Ast.GotoStmt (loc, State.first_callback_unwind_label)]
                               | None, None, Some s ->
                                   [s; Ast.GotoStmt (loc, State.callback_unwind_label)]
                               | None, None, None ->
                                   (match r19_unwind_cleanup with
                                    | Some s -> fresh_first_callback_stmt s :: unwind_stmts
                                    | None -> unwind_stmts)
                               | Some _, _, _ | _, Some _, Some _ ->
                                   Ast.static_error loc "Overlapping callback recovery markers" None)) );
                        ] )
            in
            State.r23_adapter_post_bridge := None;
            (match late_callback_cleanup, call_stmt with
             | Some _, Ast.SwitchStmt (_, _, clauses) ->
                 if List.exists (function
                      | Ast.SwitchStmtClause (_, _, branch_stmts) ->
                          List.exists (function
                            | Ast.GotoStmt (_, "#merge_late_callback_scope_end") -> true
                            | _ -> false) branch_stmts
                      | _ -> false) clauses
                 then
                   Ast.static_error loc
                     "Late callback outcome arms must fall through to their single CFG successor"
                     None
             | Some _, _ ->
                 Ast.static_error loc
                   "Late callback recovery requires an outcome switch"
                   None
             | None, _ -> ());
            (match first_callback_cleanup with
             | Some _ -> State.first_callback_normal_target := Some dst_bblock_id
             | None -> ());
            (* For late recovery, both outcome arms finish with the checked
               close block and fall through to this one CFG successor. Do not
               put arm-local Gotos in the SwitchStmt: its branches are not
               separate CFG predecessors, so block lowering may inline the
               single successor without emitting a label for it. *)
            let call_target =
              match late_callback_cleanup with
              | Some _ -> "#merge_late_callback_scope_end"
              | None -> dst_bblock_id in
            Ok
              ( [ call_stmt ],
                Mir.GotoTerminator (loc, call_target),
                [ call_target ] )
        | Undefined _ -> Error (`TrFnCall "Unknown Option kind")
      in
      let full_call_stmts, targets =
        match fn_call_rexpr with
        | FnCallOutcome
            (Ast.CallExpr
              ( call_loc,
                "VeriFast_ghost_command",
                [] (*type arguments*),
                [] (*indices, in case this is really a predicate assertion*),
                [],
                Ast.Static (*method_binding*) )) ->
            let get_start_loc loc =
              let (_, ln, col), _ = loc in
              (ln, col)
            in
            let phl = get_start_loc (Ast.lexed_loc call_loc) in
            let ghost_stmt =
              match List.find_opt
                (fun gs ->
                  let gsl = get_start_loc Ast.(gs |> stmt_loc |> lexed_loc) in
                  let gsl_l, _ = gsl in
                  let phl_l, _ = phl in
                  gsl_l = phl_l)
                !State.ghost_stmts with
              | Some stmt -> stmt
              | None ->
                  let line, column = phl in
                  Ast.static_error call_loc
                    (Printf.sprintf
                      "No translated ghost statement matches compiler ghost command at source %d:%d"
                      line column)
                    None
            in
            ([ ghost_stmt ], targets)
        | _ ->
            ( (if ListAux.is_empty fn_call_tmp_rval_ctx then call_stmts
               else
                 [
                   Ast.BlockStmt
                     ( loc,
                       (*decl list*) [],
                       fn_call_tmp_rval_ctx @ call_stmts,
                       loc,
                       ref [] );
                 ]),
              targets @ (match late_callback_cleanup with
                         | Some _ -> []
                         | None -> unwind_targets) )
      in
      let full_call_stmts = !State.pending_hrtb_projection_eq @ full_call_stmts in
      State.pending_hrtb_projection_eq := [];
      Ok (full_call_stmts, terminator, targets)

    let translate_sw_int (sw_int_data_cpn : SwitchIntDataRd.t) (loc : Ast.loc) =
      let open SwitchIntDataRd in
      Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "SwitchInt" @@ fun () ->
      let discr_cpn = discr_get sw_int_data_cpn in
      let* tmp_rvalue_binders, [ discr ] =
        Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
        translate_operands [ (discr_cpn, loc) ]
      in
      let discr_ty_cpn = discr_ty_get sw_int_data_cpn in
      let* discr_ty = translate_ty discr_ty_cpn loc in
      let values = values_get_list sw_int_data_cpn |> List.map D.decode_uint128 in
      Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
        Rocq_writer.rocq_print_small_list TranslatorArgs.rocq_writer @@ fun () ->
        values |> List.iter @@ fun v ->
          Rocq_writer.rocq_print_small_list_element TranslatorArgs.rocq_writer @@ fun () ->
            Rocq_writer.rocq_print_data TranslatorArgs.rocq_writer Vf_mir_rocq.rocq_print_u128 v
      end;
      let targets = targets_get_list sw_int_data_cpn |> List.map translate_basic_block_id in
      Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
        Rocq_writer.rocq_print_small_list TranslatorArgs.rocq_writer @@ fun () ->
        targets |> List.iter @@ fun t ->
          Rocq_writer.rocq_print_small_list_element TranslatorArgs.rocq_writer @@ fun () ->
            Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer t
      end;
      let* main_stmt, targets =
        let rec unwrap_const = function
          | Ast.ConstTypeExpr (_, te) -> unwrap_const te
          | te -> te
        in
        match unwrap_const discr_ty.vf_ty with
        | Ast.ManifestTypeExpr ((*loc*) _, Ast.Bool) -> (
            match (values, targets) with
            | [ v ], [ false_tgt; true_tgt ] when Stdint.Uint128.(zero = DecoderAux.uint128_get v)
              ->
                Ok
                  ( Ast.IfStmt
                      ( loc,
                        discr,
                        [ Ast.GotoStmt (loc, true_tgt) ],
                        [ Ast.GotoStmt (loc, false_tgt) ] ),
                    [ true_tgt; false_tgt ] )
            | _ ->
                Error
                  (`TrSwInt "Invalid SwitchTargets for a boolean discriminant"))
        | Ast.ManifestTypeExpr (_, tp) ->
            let intTp, width =
              match tp with
              | Ast.Int (signed, rank) ->
                  tp,
                  begin match rank with
                  | PtrRank -> let Some {ptr_width} = TranslatorArgs.data_model_opt in ptr_width
                  | FixedWidthRank w -> w
                  end
              | Ast.RustChar -> Ast.Int (Unsigned, FixedWidthRank 2), 2
              | _ -> failwith (Printf.sprintf "Todo: SwitchInt TerminatorKind for discriminant type %s" (Verifast0.rust_string_of_type tp))
            in
            let size = 1 lsl width in
            let branches, [], [ otherwise_target ] = Util.zip_with_remainder values targets in
            let* clauses =
              branches
              |> ListAux.try_map @@ fun (data, target) ->
                 let* v = translate_scalar_int {data; size} (Ast.ManifestTypeExpr (loc, intTp)) loc in
                 Ok (
                  Ast.SwitchStmtClause
                   ( loc,
                     v,
                     [ Ast.GotoStmt (loc, target) ] ))
            in
            let default_clause =
              [
                Ast.SwitchStmtDefaultClause
                  (loc, [ Ast.GotoStmt (loc, otherwise_target) ]);
              ]
            in
            Ok (Ast.SwitchStmt (loc, discr, clauses @ default_clause), targets)
        | _ ->
            Ast.static_error loc "Todo: SwitchInt for this discriminant type" None
      in
      if ListAux.is_empty tmp_rvalue_binders then Ok (main_stmt, targets)
      else
        Ok
          ( Ast.BlockStmt
              ( loc,
                (*decl list*) [],
                tmp_rvalue_binders @ [ main_stmt ],
                loc,
                ref [] ),
            targets )

    (* Diagnostic events are parser-inexpressible and execute through the
       verifier on the selected path. They neither assume nor produce resources.
       The exact same Body reader supplies the MIR binding and translated AST. *)
    let r9_guard_trace loc details =
      if Sys.getenv_opt "SMALLSORT_R9_GUARD_TRACE" = Some "1" &&
         State.first_callback <> None && State.late_callback <> None then begin
        if Args.body_def_hash = "" || Args.body_mir_fingerprint = "" ||
           Args.body_mir_phase = "" || !State.current_block = "" then
          Ast.static_error loc "R9 guard trace requires native body and MIR block identity" None;
        let label = Printf.sprintf
          "function=%s def_hash=%s mir_fingerprint=%s mir_phase=%s body_span=%s block=%s cleanup=%b at=%s %s"
          Args.body_name Args.body_def_hash Args.body_mir_fingerprint
          Args.body_mir_phase (Ast.string_of_loc Args.body_imp_loc)
          !State.current_block !State.current_is_cleanup
          (Ast.string_of_loc loc) details in
        [Ast.PureStmt (loc, Ast.ExprStmt (Ast.CallExpr
          (loc, "#r9_guard_event:" ^ label, [], [], [], Ast.Static)))]
      end else []

    let translate_terminator_kind (ret_place_id : string)
        (tkind_cpn : TerminatorKindRd.t) (loc : Ast.loc) =
      let open TerminatorKindRd in
      match get tkind_cpn with
      | Goto bblock_id_cpn ->
          let bb_id = translate_basic_block_id bblock_id_cpn in
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Goto" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
            Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer bb_id
          end;
          Ok ([], Mir.GotoTerminator (loc, bb_id), [ bb_id ])
      | SwitchInt sw_int_data_cpn ->
          let* sw_stmt, targets = translate_sw_int sw_int_data_cpn loc in
          Ok ([ sw_stmt ], Mir.EncodedTerminator, targets)
      | Return ->
          Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "Return";
          let result = Ast.Var (loc, ret_place_id) in
          let result =
            if TranslatorArgs.ignore_unwind_paths then result
            else
              Ast.CallExpr (loc, "returning", [], [], [ LitPat result ], Static)
          in
          Ok (r9_guard_trace loc "kind=return outcome=returning" @
              [Ast.ReturnStmt (loc, Some result)], EncodedTerminator, [])
      | Unreachable ->
          Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "Unreachable";
          Ok ([ Ast.Assert (loc, False loc) ], EncodedTerminator, [])
      | Call fn_call_data_cpn -> translate_fn_call fn_call_data_cpn loc
      | Drop drop_data_cpn ->
          let open DropData in
          let place_cpn = place_get drop_data_cpn in
          let* place, place_is_mutable = translate_place place_cpn loc in
          let target_cpn = target_get drop_data_cpn in
          let target = translate_basic_block_id target_cpn in
          let selected_path = TrName.translate_def_path (selected_drop_path_get drop_data_cpn) in
          let selected_hash = selected_drop_hash_get drop_data_cpn in
          let guard_path = TrName.translate_def_path (selected_guard_path_get drop_data_cpn) in
          let selected = List.mem (selected_path, selected_hash, guard_path)
            Args.body_tr_defs_ctx.selected_drops in
          let generated_body_key = generated_body_key_get drop_data_cpn in
          let generated_call = match Args.body_tr_defs_ctx.generated_glue with
            | None ->
                if generated_body_key <> "" then
                  Ast.static_error loc "Drop references an absent generated glue body" None;
                None
            | Some binding ->
                if generated_body_key = "" then begin
                  if selected_path = binding.glue_selected_path &&
                     selected_hash = binding.glue_selected_hash &&
                     guard_path = binding.glue_guard then
                    Ast.static_error loc "Selected Drop is missing its generated glue reference" None;
                  None
                end
                else if not selected ||
                        generated_body_key <> binding.glue_key ||
                        selected_path <> binding.glue_selected_path ||
                        selected_hash <> binding.glue_selected_hash ||
                        guard_path <> binding.glue_guard then
                  Ast.static_error loc "Drop generated glue reference does not match the selected method" None
                else Some binding.glue_key in
          if selected then begin
            if not (is_bare_local_get drop_data_cpn) || is_replace_get drop_data_cpn
                || not place_is_mutable || TranslatorArgs.ignore_unwind_paths then
              Ast.static_error loc "Qualified selected Drop requires mutable bare local, replace=false and unwind checking" None;
            let receiver_name = "__vf_drop_receiver_" ^ target in
            let receiver = Ast.Var (loc, receiver_name) in
            let address = Ast.AddressOf (loc, place) in
            let call name args = Ast.CallExpr (loc, name, [], [], List.map (fun e -> Ast.LitPat e) args, Ast.Static) in
            let ghost name args = Ast.PureStmt (loc, Ast.ExprStmt (call name args)) in
            let finish = [ghost "close_points_to" [receiver]; ghost "end_ref_mut" [receiver];
                          ghost "open_points_to" [address]] in
            (* Separately profiled fault-injection controls for the qualified
               caller interface only. The unset path is exactly the ordinary
               finish above; compiler-owned glue is never changed. *)
            let finish = match Sys.getenv_opt "SMALLSORT_DROP_RECEIVER_CONTROL", generated_call with
              | None, _ -> finish
              | Some "omit_end", Some _ ->
                  [ghost "close_points_to" [receiver]; ghost "open_points_to" [address]]
              | Some "wrong_end", Some _ ->
                  [ghost "close_points_to" [receiver]; ghost "end_ref_mut" [address];
                   ghost "open_points_to" [address]]
              | Some "duplicate_end", Some _ ->
                  [ghost "close_points_to" [receiver]; ghost "end_ref_mut" [receiver];
                   ghost "end_ref_mut" [receiver]; ghost "open_points_to" [address]]
              | Some "post_retirement_drop", _ -> finish
              | Some _, _ -> Ast.static_error loc "Unsupported generated Drop receiver diagnostic" None
            in
            let unwind_stmts, unwind_targets = translate_unwind_action (unwind_action_get drop_data_cpn) loc in
            let call_name = match generated_call with
              | Some key -> key | None -> selected_path in
            let selected_call = Ast.CallExpr (loc, call_name, [Ast.InferredTypeExpr loc], [],
              [Ast.LitPat receiver], Ast.Static) in
            let unwind_binding = match UnwindActionRd.get (unwind_action_get drop_data_cpn) with
              | UnwindActionRd.Continue -> "continue"
              | UnwindActionRd.Unreachable -> "unreachable"
              | UnwindActionRd.Terminate -> "terminate"
              | UnwindActionRd.Cleanup id -> "cleanup:" ^ translate_basic_block_id id
              | _ -> "unsupported" in
            let binding outcome = Printf.sprintf
              "kind=selected_drop outcome=%s key=%s selected=%s selected_hash=%s guard=%s normal_target=%s unwind=%s receiver=%s"
              outcome generated_body_key selected_path selected_hash guard_path
              target unwind_binding receiver_name in
            let call_stmt = Ast.SwitchStmt (loc, selected_call, [
              Ast.SwitchStmtClause (loc, call "returning" [Ast.Var (loc, "__result")],
                finish @
                (match State.r9_guard_return with
                 | Some plan
                   when Sys.getenv_opt "SMALLSORT_R9_GUARD_RETURN_RECOVERY" = Some "1" &&
                        generated_call = Some plan.r9_guard_return_key &&
                        selected_path = plan.r9_guard_return_path &&
                        selected_hash = plan.r9_guard_return_hash &&
                        guard_path = plan.r9_guard_return_guard &&
                        is_bare_local_get drop_data_cpn &&
                        not (is_replace_get drop_data_cpn) && place_is_mutable &&
                        List.mem (!State.current_block, target, !State.current_is_cleanup,
                          LocalDeclIdRd.name_get
                            (PlaceRd.local_get (place_get drop_data_cpn)))
                          plan.r9_guard_return_edges ->
                     let edge = (!State.current_block, target, !State.current_is_cleanup,
                       LocalDeclIdRd.name_get
                         (PlaceRd.local_get (place_get drop_data_cpn))) in
                     if List.mem edge !State.r9_guard_return_used then
                       Ast.static_error loc "R9 guard-return MIR edge was translated more than once" None;
                     State.r9_guard_return_used := edge :: !State.r9_guard_return_used;
                     r9_guard_trace loc (binding "returning recovery=before") @
                     [Ast.PureStmt (plan.r9_guard_return_loc,
                       Ast.BlockStmt (plan.r9_guard_return_loc, [],
                         plan.r9_guard_return_commands,
                         plan.r9_guard_return_end_loc, ref []))] @
                     r9_guard_trace loc (binding "returning recovery=complete")
                 | Some _ ->
                     Ast.static_error loc
                       "R9 guard-return marker is not bound to its exact selected Drop edge" None
                 | None -> []) @
                r9_guard_trace loc (binding "returning"));
              Ast.SwitchStmtClause (loc, call "unwinding" [],
                finish @ r9_guard_trace loc (binding "unwinding") @ unwind_stmts)]) in
            Ok ([ghost "close_points_to" [address];
                 Ast.DeclStmt (loc, [(loc, Some (Ast.PtrTypeExpr (loc,
                   Ast.StructTypeExpr (loc, Some guard_path, None, [], []))),
                   receiver_name, Some (call "fn_outcome_result" [call "create_ref_mut" [address]]),
                   (ref false, ref None))]);
                 ghost "open_points_to" [receiver]; call_stmt],
                Mir.GotoTerminator (loc, target), target :: unwind_targets)
          end else
          let unfreeze_stmts, freeze_stmts =
            if place_is_mutable then ([], [])
            else
              ( [
                  Ast.ExprStmt
                    (CallExpr
                       ( loc,
                         "std::mem::verifast::unfreeze",
                         [],
                         [],
                         [ LitPat (AddressOf (loc, place)) ],
                         Static ));
                ],
                [
                  Ast.ExprStmt
                    (CallExpr
                       ( loc,
                         "std::mem::verifast::freeze",
                         [],
                         [],
                         [ LitPat (AddressOf (loc, place)) ],
                         Static ));
                ] )
          in
          Ok
            ( unfreeze_stmts
              @ [
                  Ast.ExprStmt
                    (CallExpr
                       ( loc,
                         "std::ptr::drop_in_place",
                         [],
                         [],
                         [ LitPat (AddressOf (loc, place)) ],
                         Static ));
                ]
              @ freeze_stmts,
              Mir.GotoTerminator (loc, target),
              [ target ] )
      | Assert assert_data_cpn ->
          (* `Assert { cond, expected, target, unwind }`: continue at `target` if `cond == expected`,
             otherwise panic (i.e. unwind). With -ignore_unwind_paths the panicking branch is
             modelled as an abort, as the `Terminate` unwind action is. *)
          let open AssertData in
          let* tmp_rvalue_binders, [ cond ] =
            translate_operands [ (cond_get assert_data_cpn, loc) ]
          in
          let expected = expected_get assert_data_cpn in
          let target = translate_basic_block_id (target_get assert_data_cpn) in
          let fail_stmts, fail_targets =
            if TranslatorArgs.ignore_unwind_paths then
              ( [
                  Ast.ExprStmt
                    (Ast.CallExpr (loc, "std::process::abort", [], [], [], Ast.Static));
                ],
                [] )
            else translate_unwind_action (unwind_action_get assert_data_cpn) loc
          in
          let goto_target = [ Ast.GotoStmt (loc, target) ] in
          let if_stmt =
            if expected then Ast.IfStmt (loc, cond, goto_target, fail_stmts)
            else Ast.IfStmt (loc, cond, fail_stmts, goto_target)
          in
          Ok
            ( [ Ast.BlockStmt (loc, [], tmp_rvalue_binders @ [ if_stmt ], loc, ref []) ],
              Mir.EncodedTerminator,
              target :: fail_targets )
      | UnwindResume ->
          (* Resume has no source statement. Preserve its MIR edge and expression;
             direct qualified Drop cleanup uses the existing synthetic location. *)
          let stmt_loc = if !State.translating_selected_resume then Ast.DummyLoc else loc in
          Ok
            ( r9_guard_trace loc "kind=resume outcome=unwinding" @ [
                Ast.ReturnStmt
                  ( stmt_loc,
                    Some (Ast.CallExpr (loc, "unwinding", [], [], [], Static))
                  );
              ],
              EncodedTerminator,
              [] )
      | UnwindTerminate ->
          Ok
            ( [
                Ast.ExprStmt
                  (CallExpr (loc, "std::process::abort", [], [], [], Static));
              ],
              EncodedTerminator,
              [] )

    let translate_terminator (ret_place_id : string)
        (terminator_cpn : TerminatorRd.t) =
      let open TerminatorRd in
      let src_info_cpn = source_info_get terminator_cpn in
      let* { Mir.span = loc; Mir.scope } = translate_source_info src_info_cpn in
      let terminator_kind_cpn = kind_get terminator_cpn in
      translate_terminator_kind ret_place_id terminator_kind_cpn loc

    let translate_bin_op (bin_op_cpn : BinOpRd.t) =
      let open BinOpRd in
      match get bin_op_cpn with
      | Add -> Ok Ast.Add
      | Sub -> Ok Ast.Sub
      | Mul -> Ok Ast.Mul
      | Div -> Ok Ast.Div
      | Rem -> Ok Ast.Mod
      | BitXor -> Ok Ast.BitXor
      | BitAnd -> Ok Ast.BitAnd
      | BitOr -> Ok Ast.BitOr
      | Shl -> failwith "Todo: BinOp::Shl"
      | Shr -> failwith "Todo: BinOp::Shr"
      | Eq -> Ok Ast.Eq
      | Lt -> Ok Ast.Lt
      | Le -> Ok Ast.Le
      | Ne -> Ok Ast.Neq
      | Ge -> Ok Ast.Ge
      | Gt -> Ok Ast.Gt
      | Offset -> failwith "Todo: BinOp::Offset"
      | Undefined _ -> Error (`TrBinOp "Unknown binary operator")

    let translate_un_op (un_op_cpn : UnOpRd.t) =
      let open UnOpRd in
      match get un_op_cpn with
      | Not -> Ok Ast.Not
      | Neg -> Ok Ast.Sub
      | Undefined _ -> Error (`TrUnOp "Unknown unary operator")

    let translate_binary_operation (bin_op_data_cpn : BinaryOpDataRd.t)
        (loc : Ast.loc) =
      let open BinaryOpDataRd in
      let operator_cpn = operator_get bin_op_data_cpn in
      let* operator = translate_bin_op operator_cpn in
      let operandl_cpn = operandl_get bin_op_data_cpn in
      let* operandl = translate_operand operandl_cpn loc in
      let operandr_cpn = operandr_get bin_op_data_cpn in
      let* operandr = translate_operand operandr_cpn loc in
      Ok (operator, operandl, operandr)

    let translate_unary_operation (un_op_data_cpn : UnaryOpDataRd.t)
        (loc : Ast.loc) =
      let open UnaryOpDataRd in
      let operator_cpn = operator_get un_op_data_cpn in
      let* operator = translate_un_op operator_cpn in
      let operand_cpn = operand_get un_op_data_cpn in
      let* operand = translate_operand operand_cpn loc in
      Ok (operator, operand)

    let translate_aggregate_kind (agg_kind_cpn : AggregateKindRd.t)
        (loc : Ast.loc) =
      let open AggregateKindRd in
      match get agg_kind_cpn with
      | Array es_ty_cpn ->
          let* elem_ty = translate_ty es_ty_cpn loc in
          Ok (Mir.AggKindArray elem_ty)
      | Tuple -> Ok Mir.AggKindTuple
      | Adt adt_data_cpn ->
          let open AdtData in
          let adt_id_cpn = adt_id_get adt_data_cpn in
          let adt_def_path =
            translate_adt_def_id (D.decode_adt_def_id adt_id_cpn)
          in
          let adt_name = TrName.translate_def_path adt_def_path in
          let adt_kind =
            match AdtKindRd.get (adt_kind_get adt_data_cpn) with
            | StructKind -> Mir.Struct
            | EnumKind -> Mir.Enum
            | UnionKind -> Mir.Union
          in
          let variant_idx_cpn = variant_idx_get adt_data_cpn in
          let variant_name = variant_id_get adt_data_cpn in
          let substs_cpn = gen_args_get_list adt_data_cpn in
          let fields = fields_get_list adt_data_cpn |> List.map D.decode_aggregate_kind_adt_data_field_info in
          Ok Mir.(AggKindAdt { adt_kind; adt_name; variant_name; fields })
      | Closure _ ->
          Ok Mir.(AggKindClosure)
      | Coroutine -> failwith "Todo: AggregateKind::Coroutine"
      | CoroutineClosure -> failwith "Todo: AggregateKind::CoroutineClosure"
      | RawPtr -> failwith "Todo: AggregateKind::RawPtr"
      | Undefined _ -> Error (`TrAggregateKind "Unknown AggregateKind")

    let translate_aggregate (agg_data_cpn : AggregateDataRd.t) (loc : Ast.loc) =
      let open AggregateDataRd in
      let operands_cpn = operands_get_list agg_data_cpn in
      let operands_cpn = List.map (fun op -> (op, loc)) operands_cpn in
      let* tmp_rvalue_binders, operand_exprs =
        translate_operands operands_cpn
      in
      let agg_kind_cpn = aggregate_kind_get agg_data_cpn in
      let* agg_kind = translate_aggregate_kind agg_kind_cpn loc in
      match agg_kind with
      | AggKindArray elem_ty ->
          let init_stmts_builder (lhs_place, lhs_place_is_mutable) =
            List.mapi
              (fun i operand_expr ->
                let open Ast in
                ExprStmt
                  (AssignExpr
                     ( loc,
                       ReadArray
                         ( loc,
                           lhs_place,
                           IntLit
                             ( loc,
                               Big_int.big_int_of_int i,
                               true,
                               false,
                               NoLSuffix ) ),
                       (if lhs_place_is_mutable then Mutation
                        else Initialization),
                       operand_expr )))
              operand_exprs
          in
          Ok (`TrRvalueAggregate init_stmts_builder)
      | AggKindTuple ->
          let tuple_struct_name =
            TrTyTuple.make_tuple_type_name (List.length operands_cpn)
          in
          let init_stmts_builder (lhs_place, lhs_place_is_mutable) =
            let field_init_stmts =
              List.mapi
                (fun i init_expr ->
                  let open Ast in
                  ExprStmt
                    (AssignExpr
                       ( loc,
                         Select (loc, lhs_place, string_of_int i),
                         (if lhs_place_is_mutable then Mutation
                          else Initialization),
                         init_expr )))
                operand_exprs
            in
            tmp_rvalue_binders @ field_init_stmts
          in
          Ok (`TrRvalueAggregate init_stmts_builder)
      | AggKindClosure ->
          let init_stmts_builder (_lhs_place, _lhs_place_is_mutable) =
            tmp_rvalue_binders
          in
          Ok (`TrRvalueAggregate init_stmts_builder)
      | AggKindAdt { adt_kind; adt_name; variant_name; fields } -> (
          match adt_kind with
          | Enum ->
              let init_stmts_builder (lhs_place, lhs_place_is_mutable) =
                let arg_pats = List.map (fun e -> Ast.LitPat e) operand_exprs in
                let assignment =
                  Ast.ExprStmt
                    (AssignExpr
                       ( loc,
                         lhs_place,
                         (if lhs_place_is_mutable then Mutation
                          else Initialization),
                         CallExpr
                           ( loc,
                             adt_name ^ "::" ^ variant_name,
                             [],
                             [],
                             arg_pats,
                             Static ) ))
                in
                tmp_rvalue_binders @ [ assignment ]
              in
              Ok (`TrRvalueAggregate init_stmts_builder)
          | Union -> failwith "Todo: Unsupported Adt kind for aggregate"
          | Struct ->
              if List.length operands_cpn <> List.length fields then
                Error
                  (`TrAggregate
                    "The number of struct fields and initializing operands are \
                     different")
              else
                let init_stmts_builder (lhs_place, lhs_place_is_mutable) =
                  let field_init_stmts =
                    List.concat_map
                      (fun (({name; is_zero_size}: D.aggregate_kind_adt_data_field_info), init_expr) ->
                        if is_zero_size then [] else [
                        let open Ast in
                        ExprStmt
                          (AssignExpr
                             ( loc,
                               Select (loc, lhs_place, name),
                               (if lhs_place_is_mutable then Mutation
                                else Initialization),
                               init_expr ))
                        ])
                      (List.combine fields operand_exprs)
                  in
                  tmp_rvalue_binders @ field_init_stmts
                in
                Ok (`TrRvalueAggregate init_stmts_builder))

    let translate_rvalue (rvalue_cpn : RvalueRd.t) (loc : Ast.loc) =
      let open RvalueRd in
      let tr_operand operand =
        match operand with
        | `TrOperandCopy expr
        | `TrOperandMove (expr, _ (*place_is_mutable*))
        | `TrTypedConstantScalar expr ->
            Ok (`TrRvalueExpr expr)
        | `TrTypedConstantRvalueBinderBuilder rvalue_binder_builder ->
            Ok (`TrRvalueRvalueBinderBuilder rvalue_binder_builder)
        | `TrUnitConstant -> Ok `TrRvalueUnitConstant
        | `TrTypedConstantFn _ ->
            Error (`TrRvalue "Invalid operand translation for Rvalue")
      in
      match get rvalue_cpn with
      | Use operand_cpn ->
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Use" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
          let* operand = translate_operand operand_cpn loc in
          tr_operand operand
      | Repeat repeat_data_cpn ->
          Ast.static_error loc
            "Array repeat expressions are not yet supported" None
      | Ref ref_data_cpn ->
          let open RefData in
          let region_cpn = region_get ref_data_cpn in
          let bor_kind_cpn = bor_kind_get ref_data_cpn in
          let bor_kind = BorrowKind.get bor_kind_cpn in
          let place_cpn = place_get ref_data_cpn in
          let place_does_not_need_drop = place_does_not_need_drop_get ref_data_cpn in
          let* place_expr, place_is_mutable = translate_place place_cpn loc in
          let place_ty = decode_ty (D.decode_ty (place_ty_get ref_data_cpn)) in
          let place_kind =
            VfMirRd.PlaceKind.get (VfMirRd.Place.kind_get place_cpn)
          in
          (* Opt-in tracked ManuallyDrop shared reference; no resource creation. *)
          let track_manually_drop_shared_ref =
            match place_ty, bor_kind, place_kind with
            | `Adt (("core::mem::ManuallyDrop" | "std::mem::ManuallyDrop"),
                    _, [ `Type _ ]), Shared, Other
              when not place_is_mutable && place_does_not_need_drop -> true
            | _ -> false
          in
          let (path, line, _), _ = Ast.lexed_loc loc in
          let ignore_ref_creation =
            if track_manually_drop_shared_ref then false
            else
            bor_kind = Mut
            ||
            not place_is_mutable && place_does_not_need_drop
            ||
            (* ignore &mut E for now *)
            if TranslatorArgs.ignore_ref_creation then true
            else
              let directives =
                Util.flatmap
                  (fun { Mir.span; raw } ->
                    if
                      raw = "ignore_ref_creation"
                      &&
                      let (path', line', _), _ = Ast.lexed_loc span in
                      path' = path && line' = line
                    then [ span ]
                    else [])
                  Args.body_tr_defs_ctx.directives
              in
              match directives with
              | directive_span :: _ ->
                  if not TranslatorArgs.allow_ignore_ref_creation then
                    Ast.static_error directive_span
                      "Ignoring reference creation is not allowed; specify \
                       -allow_ignore_ref_creation on the command line to allow"
                      None;
                  true
              | [] -> false
          in
          if !(State.r23_adapter_ref_assignment) then
            (* The marked reference is represented by its place pointer only.
               The source marker has already created the RustBelt full borrow;
               do not create a TreeBorrows ref_mut_end_token here. *)
            Ok (`TrRvalueExpr (Ast.AddressOf (loc, place_expr)))
          else if ignore_ref_creation then
            Ok (`TrRvalueExpr (Ast.AddressOf (loc, place_expr)))
          else
            let is_implicit = is_implicit_get ref_data_cpn in
            (*
            Printf.printf "ref creation at %s: place_ty=%s, bor_kind=%s, place_kind=%s, is_implicit=%b\n"
              (Ast.string_of_loc loc)
              (string_of_decoded_type place_ty)
              (match bor_kind with Mut -> "Mut" | Shared -> "Shared")
              (match place_kind with MutableRef -> "MutableRef" | SharedRef -> "SharedRef" | _ -> "Other")
              is_implicit;
            *)
            let fn_name =
              match (place_ty, bor_kind, place_kind, is_implicit) with
              | `Str, Shared, SharedRef, _ -> "reborrow_str_ref"
              | `Str, Shared, _, _ -> "create_str_ref"
              | `Slice _, Mut, _, _ -> "create_slice_ref_mut"
              | `Slice _, Shared, SharedRef, _ -> "reborrow_slice_ref"
              | `Slice _, Shared, _, _ -> "create_slice_ref"
              | `Adt ("std::cell::UnsafeCell", _, _), Shared, _, _ ->
                  "create_ref_UnsafeCell"
              | _, Mut, MutableRef, true -> "reborrow_ref_mut_implicit"
              | _, Mut, MutableRef, _ -> "reborrow_ref_mut"
              | _, Mut, _, _ -> "create_ref_mut"
              | _, Shared, SharedRef, true -> "reborrow_ref_implicit"
              | _, Shared, SharedRef, _ -> "reborrow_ref"
              | _, Shared, _, _ -> "create_ref"
            in
            let expr =
              Ast.CallExpr
                ( loc,
                  fn_name,
                  [],
                  [],
                  [ LitPat (AddressOf (loc, place_expr)) ],
                  Static )
            in
            let expr =
              if TranslatorArgs.ignore_unwind_paths then expr
              else
                Ast.CallExpr
                  (loc, "fn_outcome_result", [], [], [ LitPat expr ], Static)
            in
            Ok (`TrRvalueExpr expr)
      | ThreadLocalRef ->
          Ast.static_error loc
            "Thread-local static references are not yet supported" None
      | RawPtr raw_ptr_data_cpn ->
          let open RawPtrData in
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "RawPtr_" @@ fun () ->
          let mut_cpn = mutability_get raw_ptr_data_cpn in
          let place_cpn = place_get raw_ptr_data_cpn in
          let* place_expr, place_is_mutable =
            Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
            translate_place place_cpn loc
          in
          let expr = Ast.AddressOf (loc, place_expr) in
          Ok (`TrRvalueExpr expr)
      | Cast cast_data_cpn -> (
          let cast_data = D.decode_rvalue_cast_data cast_data_cpn in
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Cast" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
            Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer
              begin match cast_data.kind with
              | PointerExposeProvenance -> "PointerExposeProvenance"
              | PointerWithExposedProvenance -> "PointerWithExposedProvenance"
              | PointerCoercion -> "PointerCoercion"
              | IntToInt -> "IntToInt"
              | FloatToInt -> "FloatToInt"
              | FloatToFloat -> "FloatToFloat"
              | IntToFloat -> "IntToFloat"
              | PtrToPtr -> "PtrToPtr"
              | FnPtrToPtr -> "FnPtrToPtr"
              | Transmute -> "Transmute"
              | Subtype -> "Subtype"
              end
          end;
          let open CastData in
          let operand_cpn = operand_get cast_data_cpn in
          let* operand =
            Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
            translate_operand operand_cpn loc
          in
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer begin fun () ->
            Rocq_writer.rocq_print_data TranslatorArgs.rocq_writer Vf_mir_rocq.rocq_print_ty
              cast_data.ty
          end;
          match cast_data with
            {operand=Copy {local; projection=[BoxAsNonNull _]}} ->
            let id = translate_local_decl_id_ local.name in
            let e =
              ( Ast.CallExpr
                ( loc,
                  "std::boxed::Box::<T, A>::as_mut_ptr",
                  [],
                  [],
                  [ LitPat (AddressOf (loc, Var (loc, id))) ],
                  Static ))
            in
            Ok (`TrRvalueExpr e)
          | _ ->
          match !(State.r23_adapter_unsize_assignment), operand with
          | true,
            (`TrOperandCopy expr | `TrOperandMove (expr, _) |
             `TrTypedConstantScalar expr) ->
              let u64_ty = Ast.ManifestTypeExpr
                (loc, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3)) in
              let data_ptr = Ast.CastExpr
                (loc, Ast.PtrTypeExpr (loc, u64_ty), expr) in
              let len = Ast.IntLit
                (loc, Big_int.big_int_of_int 3, true, true, Ast.NoLSuffix) in
              let slice_ptr = Ast.CallExpr
                (loc, "std::ptr::slice_from_raw_parts_mut", [u64_ty], [],
                 [Ast.LitPat data_ptr; Ast.LitPat len], Ast.Static) in
              (* Keep the compiler-exported temporary type. An erased MIR
                 region is recorded unchanged, but this one proof AST
                 temporary is instantiated at the explicit source interval.
                 It is a block local in that interval (never a function-scope
                 declaration), and the checked full-borrow conversion below
                 supplies its only authority. *)
              let* slice_ref_ty_info = translate_decoded_ty cast_data.ty loc in
              let slice_ref_ty = match slice_ref_ty_info.vf_ty with
                | Ast.RustRefTypeExpr (at, _, Ast.Mutable,
                    (Ast.SliceTypeExpr _ as slice_ty)) ->
                    Ast.RustRefTypeExpr
                      (at, Ast.IdentTypeExpr (at, None, "'r23_borrow"),
                       Ast.Mutable, slice_ty)
                | _ -> Ast.static_error loc
                    "R23 Unsize target proof type is not a mutable u64 slice reference"
                    None in
              (* The fat pointer is constructed with checked length metadata.
                 The type cast itself carries no ownership; the already-checked
                 source borrow plan converts the exact full_borrow resource. *)
              Ok (`TrRvalueExpr
                (Ast.CastExpr (loc, slice_ref_ty, slice_ptr)))
          | _ ->
              let* ty_info = translate_decoded_ty cast_data.ty loc in
              let ty = ty_info.vf_ty in
              match operand with
              | `TrOperandCopy expr
              | `TrOperandMove (expr, _ (*place_is_mutable*))
              | `TrTypedConstantScalar expr ->
                  Ok (`TrRvalueExpr (Ast.CastExpr (loc, ty, expr)))
              | `TrTypedConstantRvalueBinderBuilder rvalue_binder_builder ->
                  failwith "Todo: Rvalue::Cast"
                  (*Todo @Nima: We need a better design (refactor) for passing different results of operand translation*)
              | `TrTypedConstantFn fn_def_ty_cpn ->
                  let fn_name = fn_def_ty_cpn.id.name in
                  Ok (`TrRvalueExpr (Ast.CastExpr (loc, ty, Var (loc, fn_name)))))
      | BinaryOp bin_op_data_cpn ->
          let* operator, operandl, operandr =
            translate_binary_operation bin_op_data_cpn loc
          in
          let* operandl = tr_operand operandl in
          let* operandr = tr_operand operandr in
          Ok (`TrRvalueBinaryOp (operator, operandl, operandr))
      | UnaryOp un_op_data_cpn ->
          let* operator, operand =
            translate_unary_operation un_op_data_cpn loc
          in
          let* operand = tr_operand operand in
          Ok (`TrRvalueUnaryOp (operator, operand))
      | Aggregate agg_data_cpn -> translate_aggregate agg_data_cpn loc
      | Discriminant discriminant_data_cpn ->
          let place_cpn = DiscriminantData.place_get discriminant_data_cpn in
          let* place_expr, place_is_mutable = translate_place place_cpn loc in
          let (discriminant_ty: D.ty), size =
            match DiscriminantData.discriminant_ty_get discriminant_data_cpn |> D.decode_integer_type with
              Signed intTy ->
              {kind=Int intTy},
              begin match intTy with
                I8 -> 1
              | I16 -> 2
              | I32 -> 4
              | I64 -> 8
              | I128 -> 16
              | ISize -> let Some {ptr_width} = TranslatorArgs.data_model_opt in 1 lsl ptr_width
              end
            | Unsigned uintTy ->
              {kind=UInt uintTy},
              begin match uintTy with
                U8 -> 1
              | U16 -> 2
              | U32 -> 4
              | U64 -> 8
              | U128 -> 16
              | USize -> let Some {ptr_width} = TranslatorArgs.data_model_opt in 1 lsl ptr_width
              end
          in
          let* discriminant_ty = translate_decoded_ty discriminant_ty loc in
          let* discriminant_values =
            DiscriminantData.discriminant_values_get_list discriminant_data_cpn
            |> List.map D.decode_uint128
            |> ListAux.try_map (fun data -> translate_scalar_int {data; size} discriminant_ty.vf_ty loc)
          in
          Ok
            (`TrRvalueExpr
              (Ast.CallExpr
                 ( loc,
                   "#inductive_discriminant",
                   [discriminant_ty.vf_ty],
                   [],
                   List.map (fun v -> Ast.LitPat v) (place_expr :: discriminant_values),
                   Static )))
      | Undefined _ -> Error (`TrRvalue "Unknown Rvalue kind")

    (* Decoded Body provenance for storage on an invariant annotation line.
       This is a translation plan, explicitly separate from R11_EXEC. *)
    let r11_storage_plan block_id is_cleanup action mir_id local loc mir_loc =
      if Sys.getenv_opt "SMALLSORT_R11_LABEL_STORAGE_TRACE" = Some "1" &&
         State.r9_guard_return <> None && State.late_callback <> None then begin
        let same_line at =
          let (file, line, _), _ = Ast.lexed_loc at in
          let (mir_file, mir_line, _), _ = Ast.lexed_loc mir_loc in
          file = mir_file && line = mir_line in
        if List.exists (function
            | Ast.PureStmt (_, Ast.InvariantStmt (at, _)) -> same_line at
            | _ -> false) !State.ghost_stmts then
          Printf.eprintf
            "R11_STORAGE_PLAN kind=decoded_body function=%s def_hash=%s mir_fingerprint=%s mir_phase=%s body_span=%s block=%s cleanup=%b action=%s mir_local=%s local=%s ast_at=%s mir_at=%s\n%!"
            Args.body_name Args.body_def_hash Args.body_mir_fingerprint
            Args.body_mir_phase (Ast.string_of_loc Args.body_imp_loc)
            block_id is_cleanup action mir_id local
            (Ast.string_of_loc loc) (Ast.string_of_loc mir_loc)
      end

    let translate_statement_kind (statement_kind_cpn : StatementKindRd.t)
        (loc : Ast.loc) (mir_loc : Ast.loc) block_id is_cleanup =
      let open StatementKindRd in
      match get statement_kind_cpn with
      | Assign assign_data_cpn -> (
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "Assign" @@ fun () ->
          let lhs_place_cpn = AssignData.lhs_place_get assign_data_cpn in
          let* lhs_place, lhs_place_is_mutable =
            Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
            translate_place lhs_place_cpn loc
          in
          let rhs_rvalue_cpn = AssignData.rhs_rvalue_get assign_data_cpn in
          let lhs_local =
            if PlaceRd.projection_get_list lhs_place_cpn <> [] then None
            else Some (LocalDeclIdRd.name_get
              (PlaceRd.local_get lhs_place_cpn)) in
          (match State.r23_source_array_adapter, lhs_local,
                 RvalueRd.get rhs_rvalue_cpn with
           | Some plan, Some local, RvalueRd.Ref _
             when Some local = plan.r23_ref_local ->
               if plan.r23_ref_seen then
                 Ast.static_error loc "R23 array Ref assignment was translated more than once" None;
               plan.r23_ref_seen <- true;
               State.r23_adapter_ref_assignment := true
           | Some plan, Some local, RvalueRd.Cast _
             when Some local = plan.r23_unsize_local ->
               if plan.r23_unsize_seen then
                 Ast.static_error loc "R23 array Unsize assignment was translated more than once" None;
               plan.r23_unsize_seen <- true;
               State.r23_adapter_unsize_assignment := true
           | Some plan, Some local, _
             when Some local = plan.r23_ref_local ||
                  Some local = plan.r23_unsize_local ->
               Ast.static_error loc "R23 source adapter assignment changed after body admission" None
           | _ -> ());
          let rhs_rvalue_result =
            Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
              translate_rvalue rhs_rvalue_cpn loc
          in
          State.r23_adapter_ref_assignment := false;
          State.r23_adapter_unsize_assignment := false;
          let* rhs_rvalue =
            rhs_rvalue_result
          in
          match rhs_rvalue with
          | `TrRvalueExpr rhs_expr ->
              let assign_stmt =
                Ast.ExprStmt
                  (Ast.AssignExpr
                     ( loc,
                       lhs_place,
                       (if lhs_place_is_mutable then Mutation
                        else Initialization),
                       rhs_expr ))
              in
              Ok [ assign_stmt ]
          | `TrRvalueUnitConstant -> Ok []
          | `TrRvalueRvalueBinderBuilder rvalue_binder_builder ->
              (* Todo @Nima: Is this correct to use `loc` for subparts of the block that represents the assignment statement *)
              let tmp_var_name = TrName.make_tmp_var_name "" in
              let rvalue_binder_stmt = rvalue_binder_builder tmp_var_name in
              let assign_stmt =
                Ast.ExprStmt
                  (Ast.AssignExpr
                     ( loc,
                       lhs_place,
                       (if lhs_place_is_mutable then Mutation
                        else Initialization),
                       Ast.Var (loc, tmp_var_name) ))
              in
              let block_stmt =
                Ast.BlockStmt
                  ( loc,
                    (*decl list*) [],
                    [ rvalue_binder_stmt; assign_stmt ],
                    loc,
                    ref [] )
              in
              Ok [ block_stmt ]
          | `TrRvalueUnaryOp (operator, operand) -> (
              let rvalue_binder_stmts, expr =
                match operand with
                | `TrRvalueExpr expr -> ([], expr)
                | `TrRvalueRvalueBinderBuilder rvalue_binder_builder ->
                    let tmp_var_name = TrName.make_tmp_var_name "operand" in
                    let rvalue_binder_stmt =
                      rvalue_binder_builder tmp_var_name
                    in
                    ([ rvalue_binder_stmt ], Ast.Var (loc, tmp_var_name))
              in
              let assign_stmt =
                Ast.ExprStmt
                  (Ast.AssignExpr
                     ( loc,
                       lhs_place,
                       (if lhs_place_is_mutable then Mutation
                        else Initialization),
                       Ast.Operation
                         ( loc,
                           operator,
                           match operator with
                           | Sub ->
                               [
                                 IntLit
                                   ( loc,
                                     Big_int.zero_big_int,
                                     true,
                                     false,
                                     NoLSuffix );
                                 expr;
                               ]
                           | _ -> [ expr ] ) ))
              in
              match rvalue_binder_stmts with
              | [] -> Ok [ assign_stmt ]
              | _ ->
                  let block_stmt =
                    Ast.BlockStmt
                      ( loc,
                        (*decl list*) [],
                        rvalue_binder_stmts @ [ assign_stmt ],
                        loc,
                        ref [] )
                  in
                  Ok [ block_stmt ])
          | `TrRvalueBinaryOp (operator, operandl, operandr) -> (
              let rvalue_binder_stmts, exprl, exprr =
                match (operandl, operandr) with
                | `TrRvalueExpr exprl, `TrRvalueExpr exprr -> ([], exprl, exprr)
                | ( `TrRvalueExpr exprl,
                    `TrRvalueRvalueBinderBuilder rvalue_binder_builderr ) ->
                    let tmp_var_name = TrName.make_tmp_var_name "right" in
                    let rvalue_binder_stmt =
                      rvalue_binder_builderr tmp_var_name
                    in
                    ([ rvalue_binder_stmt ], exprl, Ast.Var (loc, tmp_var_name))
                | ( `TrRvalueRvalueBinderBuilder rvalue_binder_builderl,
                    `TrRvalueExpr exprr ) ->
                    let tmp_var_name = TrName.make_tmp_var_name "left" in
                    let rvalue_binder_stmt =
                      rvalue_binder_builderl tmp_var_name
                    in
                    ([ rvalue_binder_stmt ], Ast.Var (loc, tmp_var_name), exprr)
                | ( `TrRvalueRvalueBinderBuilder rvalue_binder_builderl,
                    `TrRvalueRvalueBinderBuilder rvalue_binder_builderr ) ->
                    let tmp_vl, tmp_vr =
                      ( TrName.make_tmp_var_name "left",
                        TrName.make_tmp_var_name "right" )
                    in
                    let rvbl, rvbr =
                      ( rvalue_binder_builderl tmp_vl,
                        rvalue_binder_builderr tmp_vr )
                    in
                    ( [ rvbl; rvbr ],
                      Ast.Var (loc, tmp_vl),
                      Ast.Var (loc, tmp_vr) )
              in
              let assign_stmt =
                Ast.ExprStmt
                  (Ast.AssignExpr
                     ( loc,
                       lhs_place,
                       (if lhs_place_is_mutable then Mutation
                        else Initialization),
                       Ast.Operation (loc, operator, [ exprl; exprr ]) ))
              in
              match rvalue_binder_stmts with
              | [] -> Ok [ assign_stmt ]
              | _ ->
                  let block_stmt =
                    Ast.BlockStmt
                      ( loc,
                        (*decl list*) [],
                        rvalue_binder_stmts @ [ assign_stmt ],
                        loc,
                        ref [] )
                  in
                  Ok [ block_stmt ])
          | `TrRvalueAggregate init_stmts_builder ->
              Ok (init_stmts_builder (lhs_place, lhs_place_is_mutable)))
      | SetDiscriminant -> failwith "TODO: StatementKind::SetDiscriminant"
      | StorageLive local ->
          let mir_local_id = LocalDeclIdRd.name_get local in
          let local = translate_local_decl_id local in
          r11_storage_plan block_id is_cleanup "Live" mir_local_id local loc mir_loc;
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "StorageLive" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
          Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer local;
          Ok [Ast.RustStorageLiveStmt (loc, mir_loc, mir_local_id, local)]
      | StorageDead local ->
          let mir_local_id = LocalDeclIdRd.name_get local in
          let local = translate_local_decl_id local in
          r11_storage_plan block_id is_cleanup "Dead" mir_local_id local loc mir_loc;
          Rocq_writer.rocq_print_application TranslatorArgs.rocq_writer "StorageDead" @@ fun () ->
          Rocq_writer.rocq_print_argument TranslatorArgs.rocq_writer @@ fun () ->
          Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer local;
          Ok [Ast.RustStorageDeadStmt (loc, mir_loc, mir_local_id, local)]
      | PlaceMention _ -> failwith "TODO: StatementKind::PlaceMention"
      | Assume operand_cpn ->
          let* operand = translate_operand operand_cpn loc in
          let expr =
            match operand with
            | `TrOperandCopy e
            | `TrOperandMove (e, _ (*place_is_mutable*)) -> e
            | _ ->
                failwith "TODO: StatementKind::Assume"
          in
          let assert_unchecked_call =
            Ast.ExprStmt
              (Ast.CallExpr
                 ( loc,
                   "std::hint::assert_unchecked",
                   [],
                   [],
                   [ LitPat expr ],
                   Static ))
          in
          Ok [ assert_unchecked_call ]
      | Nop ->
          Rocq_writer.rocq_print_ident TranslatorArgs.rocq_writer "Nop";
          Ok []
      | Undefined _ -> Error (`TrStatementKind "Unknown StatementKind")

    let translate_statement block_id is_cleanup (statement_cpn : StatementRd.t) =
      let open StatementRd in
      let src_info_cpn = source_info_get statement_cpn in
      let* { Mir.span = loc; Mir.scope } = translate_source_info src_info_cpn in
      let mir_loc = loc in
      (* Todo @Nima: The following `loc` substitution is due to deal with statements with their location equal to the whole body of the function.
         They prevent us from embedding ghost statements into the MIR statements. The ghost embedding approach should be changed.
         After that this `loc` changing and the `body_imp_loc` in the State are not necessary anymore. *)
      let loc =
        if loc = State.body_imp_loc then
          let spos, _ = Ast.lexed_loc State.body_imp_loc in
          Ast.Lexed (spos, spos)
        else loc
      in
      let kind_cpn = kind_get statement_cpn in
      translate_statement_kind kind_cpn loc mir_loc block_id is_cleanup

    let translate_basic_block (ret_place_id : string)
        (bblock_cpn : BasicBlockRd.t) =
      let open BasicBlockRd in
      let id_cpn = id_get bblock_cpn in
      let id = translate_basic_block_id id_cpn in
      if is_cleanup_get bblock_cpn && TranslatorArgs.ignore_unwind_paths then
        (* Todo @Nima: For now we are ignoring cleanup basic-blocks *)
        Ok None
      else
        Rocq_writer.rocq_print_big_list_element TranslatorArgs.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_tuple TranslatorArgs.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_tuple_element TranslatorArgs.rocq_writer begin fun () ->
          Rocq_writer.rocq_print_string_literal TranslatorArgs.rocq_writer id
        end;
        Rocq_writer.rocq_print_tuple_element TranslatorArgs.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_big_record TranslatorArgs.rocq_writer @@ fun () ->
        let statements_cpn = statements_get_list bblock_cpn in
        let* statements =
          Rocq_writer.rocq_print_big_record_field TranslatorArgs.rocq_writer "statements" @@ fun () ->
            Rocq_writer.rocq_print_big_list TranslatorArgs.rocq_writer @@ fun () ->
              statements_cpn |> ListAux.try_map @@ fun statement_cpn ->
                Rocq_writer.rocq_print_big_list_element TranslatorArgs.rocq_writer @@ fun () ->
                  translate_statement id (is_cleanup_get bblock_cpn) statement_cpn
        in
        let statements = List.concat statements in
        let terminator_cpn = terminator_get bblock_cpn in
        let* terminator_stmts, terminator, successors =
          Rocq_writer.rocq_print_big_record_field TranslatorArgs.rocq_writer "terminator" @@ fun () ->
            State.translating_selected_resume := List.mem id !State.selected_resume_targets;
            State.current_block := id;
            State.current_is_cleanup := is_cleanup_get bblock_cpn;
            let result = translate_terminator ret_place_id terminator_cpn in
            State.translating_selected_resume := false;
            State.current_block := "";
            State.current_is_cleanup := false;
            result
        in
        let bblock : Mir.basic_block =
          {
            id;
            statements;
            terminator_stmts;
            terminator;
            successors;
            external_predecessor_count = 0;
            internal_predecessor_count = 0;
            walk_state = NotSeen;
            is_block_head = false;
            parent = None;
            children = [];
          }
        in
        Ok (Some bblock)

    let find_blocks (bblocks : Mir.basic_block list) =
      let open Mir in
      let explicit_block_heads_table = Hashtbl.create 10 in
      let explicit_block_starts_table = Hashtbl.create 10 in
      let bblocks_table = Hashtbl.create 100 in
      let explicit_block_ends = ref [] in
      let loop_spec_blocks = ref [] in
      bblocks
      |> List.iter (fun (bb : Mir.basic_block) ->
             match bb.terminator_stmts with
             | Ast.BlockStmt
                 ( Ast.Lexed (startPos, _),
                   [],
                   [PureStmt (_, SpecStmt (_, _, _)) as stmt],
                   Ast.Lexed (_, endPos),
                   _ )
               ::stmts
               ->
                 loop_spec_blocks := (startPos, endPos, bb.id)::!loop_spec_blocks;
                 let fixed_bb =
                   {
                     bb with
                     terminator_stmts = stmt::stmts
                   }
                 in
                 Hashtbl.add bblocks_table bb.id fixed_bb
             | [
              Ast.BlockStmt
                ( l,
                  decls,
                  [
                    ExprStmt
                      (CallExpr
                        (_, "#ghost_decl_block_start", [], [], [], Static));
                  ],
                  closeBraceLoc,
                  _ );
             ] ->
                 let id =
                   Printf.sprintf "bh%d"
                     (Hashtbl.length explicit_block_heads_table)
                 in
                 let fixed_bb =
                   {
                     bb with
                     terminator_stmts = [];
                     terminator = GotoTerminator (l, id);
                     successors = [ id ];
                   }
                 in
                 let bh =
                   { bb with id; is_block_head = true; statements = [] }
                 in
                 Hashtbl.add bblocks_table bb.id fixed_bb;
                 Hashtbl.add bblocks_table id bh;
                 Hashtbl.add explicit_block_heads_table closeBraceLoc bh;
                 Hashtbl.add explicit_block_starts_table closeBraceLoc bb.id
             | [
              Ast.ExprStmt
                (CallExpr
                  (closeBraceLoc, "#ghost_decl_block_end", [], [], [], Static));
             ] ->
                 explicit_block_ends :=
                   (closeBraceLoc, bb.terminator, bb) :: !explicit_block_ends
             | _ -> Hashtbl.add bblocks_table bb.id bb);
      let loop_spec_blocks = !loop_spec_blocks in
      !explicit_block_ends
      |> List.iter (fun (closeBraceLoc, gotoStmt, (bb : Mir.basic_block)) ->
             let head_bb =
               Hashtbl.find explicit_block_heads_table closeBraceLoc
             in
             Hashtbl.add bblocks_table bb.id
               {
                 bb with
                 terminator_stmts = [];
                 terminator = gotoStmt;
                 successors = head_bb.id :: bb.successors;
               });
      let find_innermost_loop_spec_block l =
        match l with
        | Ast.Lexed (pos, _) ->
          let enclosing_loop_spec_blocks =
            loop_spec_blocks
            |> List.filter (fun (startPos, endPos, _) -> LocAux.loc0_contains_srcpos (startPos, endPos) pos)
          in
          begin match enclosing_loop_spec_blocks with
          | [] -> None
          | block::blocks ->
            let rec iter block blocks =
              match blocks with
              | [] -> block
              | block'::blocks' ->
                let ((_, line1, col1), e1, _) = block in
                let ((_, line2, col2), e2, _) = block' in
                if line1 < line2 || (line1 = line2 && col1 < col2) then
                  iter block' blocks'
                else
                  iter block blocks'
            in
            Some (iter block blocks)
          end
        | _ -> None
      in
      let process_bb_wrt_loop_spec_blocks (bb : basic_block) =
        (* 1. Split the basic block such that all statements and the terminator belong to the same innermost loop spec block
         * 2. Add the head of the innermost loop spec block as a (fictional) successor of the basic block
         *)
        let terminator_loop_spec_block =
          match bb.terminator_stmts with
          | s::ss -> find_innermost_loop_spec_block (Ast.stmt_loc s)
          | _ -> None
        in
        let stmts = List.map (fun s -> (find_innermost_loop_spec_block (Ast.stmt_loc s), s)) bb.statements in
        let rec iter bb stmts =
          match stmts with
            [] ->
            begin match terminator_loop_spec_block with
            | None -> ()
            | Some (_, _, loop_head_bb_id) ->
              bb.successors <- loop_head_bb_id :: bb.successors;
            end
          | (block, stmt)::stmts ->
            let stmts_in_block, stmts =
              let rec iter1 stmts_in_block stmts =
                match stmts with
                | (block', stmt')::stmts' when block = block' ->
                    iter1 (stmt'::stmts_in_block) stmts'
                | _ -> List.rev stmts_in_block, stmts
              in
              iter1 [stmt] stmts
            in
            if stmts = [] && block = terminator_loop_spec_block then
              iter bb stmts
            else
              let new_bb = 
                {
                  bb with
                  id = Printf.sprintf "%s_split%d"
                    bb.id (Hashtbl.length bblocks_table);
                  statements = List.map snd stmts;
                  external_predecessor_count = 0;
                  internal_predecessor_count = 0;
                  walk_state = NotSeen;
                  is_block_head = false;
                  parent = None;
                  children = [];
                }
              in
              Hashtbl.add bblocks_table new_bb.id new_bb;
              bb.statements <- stmts_in_block;
              bb.terminator_stmts <- [];
              bb.terminator <- GotoTerminator (Ast.stmt_loc stmt, new_bb.id);
              bb.successors <- [ new_bb.id ] @ begin match block with
                | None -> []
                | Some (_, _, loop_head_bb_id) -> [ loop_head_bb_id ]
              end;
              iter new_bb stmts
        in
        iter bb stmts
      in
      let entry_id = (List.hd bblocks).id in
      let toplevel_blocks = ref [] in
      let rec set_parent (bb : basic_block) k k' path =
        if k' = k then ()
        else
          let (bb' :: path) = path in
          match bb'.parent with
          | None ->
              (*Printf.printf "Setting %s.parent <- Some %s\n" bb'.id bb.id;*)
              bb'.parent <- Some bb;
              set_parent bb k (k' - 1) path
          | Some bb'' ->
              let (Walking (k'', path')) = bb''.walk_state in
              if k'' < k then (
                (*Printf.printf "Setting %s.parent <- Some %s\n" bb'.id bb.id;*)
                bb'.parent <- Some bb;
                set_parent bb k (k' - 1) path)
              else if k'' = k then ()
              else set_parent bb k k'' path'
      in
      let rec iter path k bb_id =
        let bb = Hashtbl.find bblocks_table bb_id in
        match bb.walk_state with
        | NotSeen -> (
            process_bb_wrt_loop_spec_blocks bb;
            bb.external_predecessor_count <- bb.external_predecessor_count + 1;
            let path = bb :: path in
            bb.walk_state <- Walking (k, path);
            bb.successors
            |> List.iter (fun succ_id -> iter path (k + 1) succ_id);
            bb.walk_state <- Exhausted;
            match bb.parent with
            | None -> toplevel_blocks := bb :: !toplevel_blocks
            | Some bb' -> bb'.children <- bb :: bb'.children)
        | Walking (k', _) ->
            (* R10 read-only binding receipt from the same decoded Body and
               reconstructed CFG. This is discovery, not path execution. *)
            if Sys.getenv_opt "SMALLSORT_R9_GUARD_TRACE" = Some "1" &&
               State.first_callback <> None && State.late_callback <> None then begin
              let from = match path with parent :: _ -> parent.id | [] -> "NONE" in
              let head_loc = match bb.statements @ bb.terminator_stmts with
                | stmt :: _ -> Ast.stmt_loc stmt | [] -> Args.body_imp_loc in
              Printf.eprintf
                "R10_LOOP_BINDING kind=reconstructed_cfg function=%s def_hash=%s mir_fingerprint=%s mir_phase=%s body_span=%s head=%s from=%s head_loc=%s\n%!"
                Args.body_name Args.body_def_hash Args.body_mir_fingerprint
                Args.body_mir_phase (Ast.string_of_loc Args.body_imp_loc)
                bb.id from (Ast.string_of_loc head_loc)
            end;
            bb.internal_predecessor_count <- bb.internal_predecessor_count + 1;
            (*Printf.printf "Found a loop with head at rank %d: %s\n" k' (String.concat " -> " (List.map (fun (bb: basic_block) -> bb.id) (List.rev (bb::path))));*)
            bb.is_block_head <- true;
            set_parent bb k' (k - 1) path
        | Exhausted -> (
            bb.external_predecessor_count <- bb.external_predecessor_count + 1;
            match bb.parent with
            | None -> ()
            | Some bb' -> (
                match bb'.walk_state with
                | Walking (k', _) -> set_parent bb' k' (k - 1) path
                | Exhausted ->
                    failwith
                      (Printf.sprintf
                         "Error: found a loop with head %s and children %s and \
                          a secondary entry point with path %s"
                         bb'.id
                         (String.concat ", "
                            (List.map
                               (fun (bb : basic_block) -> bb.id)
                               bb'.children))
                         (String.concat " -> "
                            (List.rev
                               (List.map
                                  (fun (bb : basic_block) -> bb.id)
                                  (bb :: path)))))))
      in
      iter [] 0 entry_id;
      List.iter (fun (close_loc, _) ->
        let head : Mir.basic_block = Hashtbl.find explicit_block_heads_table close_loc in
        let entry_id = Hashtbl.find explicit_block_starts_table close_loc in
        let end_bb : Mir.basic_block =
          match List.filter (fun (loc, _, _) -> loc = close_loc) !explicit_block_ends with
          | [(_, _, original)] -> Hashtbl.find bblocks_table original.id
          | _ -> Ast.static_error close_loc "Expected one callback lifetime end marker" None
        in
        let rec scoped_ids (bb : Mir.basic_block) =
          bb.id :: Util.flatmap scoped_ids bb.children
        in
        let ids = scoped_ids head in
        if not (List.mem end_bb.id ids) ||
           not (List.mem head.id end_bb.successors) ||
           not (List.exists (fun id -> id <> head.id && not (List.mem id ids)) end_bb.successors) ||
           List.exists (fun id -> id <> head.id && List.mem id ids) end_bb.successors then
          Ast.static_error close_loc "Callback lifetime end must leave its reconstructed prefix" None;
        Hashtbl.iter (fun _ (bb : Mir.basic_block) ->
          if not (List.mem bb.id ids) then
            List.iter (fun successor ->
              if List.mem successor ids &&
                 not (bb.id = entry_id && successor = head.id) then
                Ast.static_error close_loc "A goto enters an ended callback lifetime" None)
              bb.successors)
          bblocks_table)
        State.strict_lft_scope_ends;
      !toplevel_blocks

    let rec translate_to_vf_basic_block
        ({
           id;
           statements = stmts0;
           terminator_stmts = trmStmts;
           terminator = trm;
           successors;
           external_predecessor_count;
           internal_predecessor_count;
           is_block_head;
           children;
         } :
          Mir.basic_block) =
      let stmts1 = stmts0 @ trmStmts in
      let stmts =
        stmts1
        @
        match trm with
        | GotoTerminator (l, lbl) -> [ Ast.GotoStmt (l, lbl) ]
        | EncodedTerminator -> []
      in
      let loc = stmts |> List.hd |> Ast.stmt_loc in
      let predecessor_count, stmts, trm =
        if is_block_head then
          match (trmStmts, trm) with
          | ( [
                Ast.BlockStmt
                  ( l,
                    decls,
                    [
                      ExprStmt
                        (CallExpr
                          (_, "#ghost_decl_block_start", [], [], [], Static));
                    ],
                    closeBraceLoc,
                    _ );
              ],
              GotoTerminator (lg, target) ) ->
              let children_stmts =
                translate_basic_blocks_to_stmts children []
              in
              let strict_scope_start =
                match List.assoc_opt closeBraceLoc State.strict_lft_scope_ends with
                | None -> []
                | Some name ->
                    [ Ast.ExprStmt
                        (Ast.CallExpr
                           (l, "#strict_lft_binding_scope",
                            [Ast.IdentTypeExpr (l, None, name)], [], [], Ast.Static)) ]
              in
              let r23_scoped_decls =
                match State.r23_source_array_adapter with
                | Some plan
                  when (let ((file, line, _), _) = Ast.lexed_loc l
                        and ((pre_file, pre_line, _), _) =
                          Ast.lexed_loc plan.r23_pre_marker_loc in
                        file = pre_file && line = pre_line) ->
                    if plan.r23_scope_decls_inserted then
                      Ast.static_error plan.r23_pre_marker_loc
                        "R23 scoped local declarations were inserted more than once"
                        None;
                    plan.r23_scope_decls_inserted <- true;
                    plan.r23_scoped_local_decls
                | _ -> []
              in
              ( external_predecessor_count + internal_predecessor_count,
                [
                  Ast.BlockStmt
                    ( loc,
                      decls,
                      strict_scope_start @ r23_scoped_decls @
                      (Ast.LabelStmt (loc, id)
                      :: (stmts0
                         @ [ Ast.GotoStmt (lg, target) ]
                         @ children_stmts)),
                      closeBraceLoc,
                      ref [] );
                ],
                Mir.EncodedTerminator )
          | _ ->
              (* The admitted late-binding declaration must remain first in
                 the Rust source block. Relocation leaves its exact Noop at
                 that position; retain it inside the checked loop body while
                 recognizing the immediately following invariant. Never cross
                 any executable or ghost-resource statement. *)
              let stmts =
                match State.r9_guard_return, State.late_callback, stmts with
                | Some _, Some plan,
                  (Ast.NoopStmt l as placeholder) ::
                  (Ast.PureStmt (_, InvariantStmt _) as invariant) :: rest
                  when l = plan.late_original_decl_loc ->
                    invariant :: placeholder :: rest
                | _ -> stmts
              in
              let predecessor_count, stmt =
                match stmts with
                | Ast.PureStmt (lp, InvariantStmt (linv, inv)) :: stmts ->
                    let children_stmts =
                      translate_basic_blocks_to_stmts children
                        [
                          ( id,
                            internal_predecessor_count,
                            loc,
                            [],
                            Mir.EncodedTerminator );
                        ]
                    in
                    ( external_predecessor_count,
                      Ast.WhileStmt
                        ( loc,
                          True loc,
                          Some (LoopInv inv),
                          None,
                          stmts @ children_stmts,
                          [] ) )
                | Ast.PureStmt (lp, Ast.SpecStmt (lspec, req, ens)) :: stmts ->
                    let children_stmts =
                      translate_basic_blocks_to_stmts children
                        [
                          ( id,
                            internal_predecessor_count,
                            loc,
                            [],
                            Mir.EncodedTerminator );
                        ]
                    in
                    let stmts = stmts @ children_stmts in
                    let rec move_recursive_call_to_end stmts =
                      match stmts with
                      | [] -> []
                      | Ast.PureStmt
                          (
                            lstmt,
                            Ast.ExprStmt
                              (Ast.CallExpr
                                (lcall, "recursive_call", [], [], [], Static))) as stmt
                        :: stmts ->
                          let rec collect_epilog epilog_stmts stmts =
                            match stmts with
                            | [] -> List.rev epilog_stmts
                            | Ast.GotoStmt (lgoto, lbl) as stmt :: stmts ->
                                let rec find_label stmts =
                                  match stmts with
                                  | [] -> Ast.static_error lcall "This recursive_call() is not supported in this position" None
                                  | Ast.LabelStmt (llabel, id) as stmt :: stmts when id = lbl ->
                                      stmt :: collect_epilog epilog_stmts stmts
                                  | stmt :: stmts ->
                                      stmt :: find_label stmts
                                in
                                stmt :: find_label stmts
                            | stmt :: stmts ->
                                collect_epilog (stmt :: epilog_stmts) stmts
                          in
                          collect_epilog [stmt] stmts
                      | stmt :: stmts ->
                          stmt :: move_recursive_call_to_end stmts
                    in
                    ( external_predecessor_count,
                      Ast.WhileStmt
                        ( loc,
                          True loc,
                          Some (LoopSpec (req, ens)),
                          None,
                          move_recursive_call_to_end stmts,
                          [] ) )
                | _ ->
                    let children_stmts =
                      translate_basic_blocks_to_stmts children []
                    in
                    ( external_predecessor_count + internal_predecessor_count,
                      Ast.BlockStmt
                        ( loc,
                          [],
                          Ast.LabelStmt (loc, id) :: (stmts @ children_stmts),
                          loc,
                          ref [] ) )
              in
              (predecessor_count, [ stmt ], EncodedTerminator)
        else
          (external_predecessor_count + internal_predecessor_count, stmts1, trm)
      in
      (id, predecessor_count, loc, stmts, trm)

    and translate_basic_blocks_to_stmts (bblocks : Mir.basic_block list) epilog
        =
      let bbs = List.map translate_to_vf_basic_block bblocks @ epilog in
      let rec iter trm bbs =
        match (trm, bbs) with
        | Mir.EncodedTerminator, (id, predecessor_count, loc, stmts, trm) :: bbs
          ->
            (Ast.LabelStmt (loc, id) :: stmts) @ iter trm bbs
        | Mir.EncodedTerminator, [] -> []
        | ( Mir.GotoTerminator (l, lbl),
            (id, predecessor_count, loc, stmts, trm) :: bbs ) ->
            if predecessor_count = 1 && lbl = id then stmts @ iter trm bbs
            else
              (Ast.GotoStmt (l, lbl) :: Ast.LabelStmt (loc, id) :: stmts)
              @ iter trm bbs
        | Mir.GotoTerminator (l, lbl), [] -> [ Ast.GotoStmt (l, lbl) ]
      in
      iter EncodedTerminator bbs

    let translate_var_debug_info_contents (vdic_cpn : VarDebugInfoContentsRd.t)
        (loc : Ast.loc) =
      let open VarDebugInfoContentsRd in
      match get vdic_cpn with
      | Place place_cpn -> (
          let* place, place_is_mutable = translate_place place_cpn loc in
          match place with
          | Ast.Var ((*loc*) _, id) -> Ok (Mir.VdiiPlace { id })
          | _ -> failwith "Todo VarDebugInfoContents Place")
      | Const constant_cpn -> Ok Mir.VdiiConstant
      | Undefined _ ->
          Error (`TrVarDebugInfoContents "Unknown variable debug info kind")

    let translate_var_debug_info (vdi_cpn : VarDebugInfoRd.t) =
      let open VarDebugInfoRd in
      let name_cpn = name_get vdi_cpn in
      let name = translate_symbol name_cpn in
      let src_info_cpn = source_info_get vdi_cpn in
      let* src_info = translate_source_info src_info_cpn in
      let value_cpn = value_get vdi_cpn in
      let* value = translate_var_debug_info_contents value_cpn src_info.span in
      Ok ({ internal = value; surf_name = name } : Mir.var_debug_info)
  end
  (* TrBody *)

  let rec mk_list_pat l = function
    | [] -> Ast.LitPat (Var (l, "nil"))
    | h :: t -> Ast.CtorPat (l, "cons", [ h; mk_list_pat l t ])

  let mk_send_expr loc te =
    let open Ast in
    CallExpr
      ( loc,
        "is_Send",
        [],
        [],
        [
          LitPat
            (Typeid (loc, TypeExpr te));
        ],
        Static )

  let mk_send_tparam_expr loc tparam =
    let open Ast in
    mk_send_expr loc (IdentTypeExpr (loc, None, tparam))

  let mk_send_asn loc te =
    let open Ast in
    ExprAsn
      ( loc,
        mk_send_expr loc te )

  let mk_send_tparam_asn loc tparam =
    let open Ast in
    mk_send_asn loc (IdentTypeExpr (loc, None, tparam))

  let mk_sync_expr loc te =
    let open Ast in
    CallExpr
      ( loc,
        "is_Sync",
        [],
        [],
        [
          LitPat
            (Typeid (loc, TypeExpr te));
        ],
        Static )
  
  let mk_sync_tparam_expr loc tparam =
    let open Ast in
    mk_sync_expr loc (IdentTypeExpr (loc, None, tparam))
  
  let mk_sync_asn loc te =
    let open Ast in
    ExprAsn
      ( loc,
        CallExpr
          ( loc,
            "is_Sync",
            [],
            [],
            [
              LitPat
                (Typeid (loc, TypeExpr te));
            ],
            Static ) )
  
  let mk_sync_tparam_asn loc tparam =
    mk_sync_asn loc (IdentTypeExpr (loc, None, tparam))

  let gen_own_asn (adt_defs : Mir.adt_def_tr list) (thread_id : Ast.expr)
      (loc : Ast.loc) (v : Ast.expr) (ty_info : Mir.ty_info) =
    let raw_ty = ty_info.vf_ty in
    let RustBelt.{ size; own; shr } = ty_info.interp in
    match own thread_id v with
    | Ok asn -> Ok asn
    | Error estr ->
        Ast.static_error loc ("Owner assertion function error: " ^ estr) None

  let gen_own_asns (adt_defs : Mir.adt_def_tr list) (loc : Ast.loc)
      (thread_id : Ast.expr) (vs : (Ast.loc * Ast.expr * Mir.ty_info) list) =
    let* ty_asns =
      ListAux.try_map
        (fun (v_loc, v, v_ty) -> gen_own_asn adt_defs thread_id v_loc v v_ty)
        vs
    in
    let ty_asns =
      List.filter
        (fun asn -> match asn with Ast.True _ -> false | _ -> true)
        ty_asns
    in
    Ok (AstAux.list_to_sep_conj (List.map (fun asn -> (loc, asn)) ty_asns) None)

  let rec type_is_trivially_droppable = function
    | Ast.ManifestTypeExpr
        ( _,
          ( Int (_, _)
          | RustRefType _ | PtrType _ | Bool | Float | Double | LongDouble ) )
    | Ast.PtrTypeExpr (_, _)
    | Ast.RustRefTypeExpr (_, _, _, _) ->
        true
    | Ast.StructTypeExpr
        (_, Some ("std::ptr::NonNull" | "std::marker::PhantomData"), _, _, _) ->
        true
    | Ast.ConstructedTypeExpr (_, "std::option::Option", [ arg ]) ->
        type_is_trivially_droppable arg
    | _ -> false

  let gen_adt_drop_proof_oblig (adt_defs : Mir.adt_def_tr list)
      (adt_def_loc : Ast.loc) (adt_name : string) (tparams : (string * Ast.tparam_bounds_expr) list)
      (adt_fields : (Ast.loc * string * Mir.ty_info) list) =
    let open Ast in
    let targs =
      List.map (fun (x, _) -> IdentTypeExpr (adt_def_loc, None, x)) tparams
    in
    let pre =
      CallExpr
        ( adt_def_loc,
          adt_name ^ "_own",
          targs,
          [],
          [ VarPat (adt_def_loc, "_t"); VarPat (adt_def_loc, "_v") ],
          if targs = [] then PredFamCall else PredCtorCall )
    in
    let post =
      Result.get_ok
      @@ gen_own_asns adt_defs adt_def_loc
           (Var (adt_def_loc, "_t"))
           (Util.flatmap
              (fun (loc, id, ty) ->
                if type_is_trivially_droppable ty.Mir.vf_ty then []
                else [ (loc, Select (loc, Var (loc, "_v"), id), ty) ])
              adt_fields)
    in
    let post = match post with None -> True adt_def_loc | Some post -> post in
    Func
      ( adt_def_loc,
        Lemma
          ( false
            (*indicates whether an axiom should be generated for this lemma*),
            None (*trigger*) ),
        tparams (*type parameters*),
        None (*return type*),
        adt_name ^ "_drop",
        [],
        false (*nonghost_callers_only*),
        (None, None)
        (*implemented function type, with function type type arguments and function type arguments*),
        Some (pre, ("result", post)) (*contract*),
        false (*terminates*),
        None (*body*),
        false (*virtual*),
        [] (*overrides*) )

  let gen_contract (adt_defs : Mir.adt_def_tr list) (contract_loc : Ast.loc)
      (lft_vars : string list) (outlives_clauses : (string * string) list)
      (send_tparams : string list) (sync_tparams : string list)
      (params : (Ast.loc * string * Mir.ty_info) list)
      (ret : Ast.loc * Mir.ty_info) =
    let ret_loc, ret_ty = ret in
    let open Ast in
    let bind_pat_b n = VarPat (contract_loc, n) in
    let lit_pat_b n = LitPat (Var (contract_loc, n)) in
    (* Todo @Nima: Move RustBelt token, etc. constructors like the following to the RustBelt module so
       The hard-coded names will be in the same place and the code will be reusable *)
    let nonatomic_token_b pat =
      CallExpr
        ( contract_loc,
          "thread_token",
          [] (*type arguments*),
          [] (*indices*),
          [ pat ] (*arguments*),
          Static )
    in
    let thread_id_name = "_t" in
    let ret_ty_has_elided_lifetimes =
      let rec check_type_expr state te =
        match te with
        | IdentTypeExpr (_, _, x) when String.starts_with ~prefix:"'_" x -> true
        | ManifestTypeExpr (_, tp) -> state
        | _ -> type_expr_fold_open check_type_expr state te
      in
      check_type_expr false ret_ty.vf_ty
    in
    let is_in_out_param (_, _, ty) =
      match ty.Mir.vf_ty with
      | RustRefTypeExpr (_, IdentTypeExpr (_, _, x), Mutable, _)
        when (not ret_ty_has_elided_lifetimes)
             && String.starts_with ~prefix:"'_" x ->
          true
      | _ -> false
    in
    let in_out_params, in_params = params |> List.partition is_in_out_param in
    let add_in_out_param_asns suffix asn =
      List.fold_right
        (fun (loc, id, ty) asn ->
          let (Some pointee_fbc) = ty.Mir.interp.pointee_fbc in
          let (Ok pointee_fbc) =
            pointee_fbc (Var (loc, thread_id_name)) id suffix
          in
          Sep (loc, pointee_fbc, asn))
        in_out_params asn
    in
    let pre_na_token =
      Sep
        ( contract_loc,
          nonatomic_token_b (bind_pat_b thread_id_name),
          Operation
            ( contract_loc,
              Eq,
              [ Var (contract_loc, "_t"); Var (contract_loc, "currentThread") ]
            ) )
    in
    let post_na_token = nonatomic_token_b (lit_pat_b thread_id_name) in
    let lft_token_b q_pat_b n =
      let coef_n = "_q_" ^ n in
      CoefAsn
        ( contract_loc,
          q_pat_b coef_n,
          CallExpr
            ( contract_loc,
              "lifetime_token",
              [] (*type arguments*),
              [] (*indices*),
              [ LitPat (Rust_parser.expr_of_lft_param contract_loc ("'" ^ n)) ]
              (*arguments*),
              Static ) )
    in
    let pre_lft_tks =
      if List.length lft_vars <= 1 then
        List.map (fun lft_var -> lft_token_b bind_pat_b lft_var) lft_vars
      else List.map (fun lft_var -> lft_token_b bind_pat_b lft_var) lft_vars
    in
    let outlives_asns =
      outlives_clauses
      |> List.map @@ fun (r1, r2) ->
         Operation
           ( contract_loc,
             Eq,
             [
               CallExpr
                 ( contract_loc,
                   "lifetime_inclusion",
                   [],
                   [],
                   [
                     LitPat (Rust_parser.expr_of_lft_param contract_loc r2);
                     LitPat (Rust_parser.expr_of_lft_param contract_loc r1);
                   ],
                   Static );
               True contract_loc;
             ] )
    in
    let send_asns = send_tparams |> List.map (mk_send_tparam_asn contract_loc) in
    let sync_asns = sync_tparams |> List.map (mk_sync_tparam_asn contract_loc) in
    let pre_lft_tks = pre_lft_tks @ outlives_asns @ send_asns @ sync_asns in
    let post_lft_tks =
      List.map (fun lft_var -> lft_token_b lit_pat_b lft_var) lft_vars
    in
    let* params_ty_asns =
      gen_own_asns adt_defs contract_loc
        (Var (contract_loc, thread_id_name))
        (List.map (fun (loc, id, ty) -> (loc, Var (loc, id), ty)) in_params)
    in
    let pre_asn =
      AstAux.list_to_sep_conj
        (List.map (fun asn -> (contract_loc, asn)) pre_lft_tks)
        params_ty_asns
    in
    let pre_asn =
      match pre_asn with None -> EmpAsn contract_loc | Some asn -> asn
    in
    let pre_asn =
      Sep (contract_loc, pre_na_token, add_in_out_param_asns "0" pre_asn)
    in
    let* ret_ty_asn =
      gen_own_asn adt_defs
        (Var (contract_loc, thread_id_name))
        ret_loc
        (Var (ret_loc, "result"))
        ret_ty
    in
    let (Some post_asn) =
      AstAux.list_to_sep_conj
        (List.map (fun asn -> (contract_loc, asn)) post_lft_tks)
        (Some (add_in_out_param_asns "1" ret_ty_asn))
      (*might be just True*)
    in
    let post_asn = Sep (contract_loc, post_na_token, post_asn) in
    let (Some unwind_post_asn) =
      AstAux.list_to_sep_conj
        (List.map (fun asn -> (contract_loc, asn)) post_lft_tks)
        (Some (add_in_out_param_asns "1" (EmpAsn contract_loc)))
      (*might be just True*)
    in
    let unwind_post_asn = Sep (contract_loc, post_na_token, unwind_post_asn) in
    Ok
      ( pre_asn,
        Rust_parser.mk_outcome_post contract_loc post_asn unwind_post_asn )

  let drop_effect_name self_ty =
    let suffix = "CopyOnDrop" in
    if not (String.ends_with ~suffix self_ty) then None
    else
      let prefix_len = String.length self_ty - String.length suffix in
      if prefix_len = 0 then Some "CopyOnDrop_drop_effect"
      else if prefix_len >= 2
          && String.sub self_ty (prefix_len - 2) 2 = "::"
      then Some (String.sub self_ty 0 prefix_len ^ "CopyOnDrop_drop_effect")
      else None

  let loc_source_file =
    let rec aux = function
      | Ast.Lexed ((path, _, _), _) -> Some path
      | Ast.MacroExpansion (_, body_loc) -> aux body_loc
      | Ast.MacroParamExpansion (param_loc, _) -> aux param_loc
      | Ast.DummyLoc -> None
    in
    aux

  let concrete_drop_effect_decl ghost_decl_map adt_defs self_ty self_ty_targs
      self_lft_args =
    let open Ast in
    match drop_effect_name self_ty with
    | None -> None
    | Some effect_name ->
      let candidates = List.filter (fun (name, _) -> name = effect_name) ghost_decl_map in
      begin match candidates with
      | [] -> None
      | _ ->
        let invalid () =
          let loc = match candidates with
            | (_, decl)::_ ->
              begin match AstAux.decl_loc_name_and_name_setter decl with
              | Some (loc, _, _) -> loc
              | None -> Ast.dummy_loc
              end
            | [] -> Ast.dummy_loc
          in
          static_error loc
            "Malformed CopyOnDrop_drop_effect opt-in predicate" None
        in
        let guard = List.find_opt (fun (adt_def : Mir.adt_def_tr) -> adt_def.name = self_ty) adt_defs in
        let guard_is_qualified = match guard with
          | Some ({ loc = guard_loc; tparams = []; lft_params = []; fds_no_zst; def = Struct (_, _, [], Left (_, _, _, _), attrs); _ } : Mir.adt_def_tr) ->
              let layout_is_exact = match rust_concrete_guard_layout attrs with
                | Some layout -> layout.source_def_path = self_ty
                    && layout.target_triple = "x86_64-unknown-linux-gnu"
                    && layout.pointer_width = 64
                | None -> false
              in
              let fields_are_exact = match fds_no_zst with
                | [ { name = "src"; ty = { vf_ty = PtrTypeExpr (_, ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 3))); _ }; _ };
                    { name = "dst"; ty = { vf_ty = PtrTypeExpr (_, ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 3))); _ }; _ };
                    { name = "len"; ty = { vf_ty = ManifestTypeExpr (_, Int (Unsigned, PtrRank)); _ }; _ } ] -> true
                | _ -> false
              in
              layout_is_exact && fields_are_exact
                && self_ty_targs = [] && self_lft_args = []
                && loc_source_file guard_loc <> None
          | _ -> false
        in
        if not guard_is_qualified then invalid ();
        (* The Rust ghost parser intentionally normalizes `*const T` and
           `*mut T` to the same PtrTypeExpr. Keep the declaration's exact
           ordered source/destination names and u64 pointee types here; the
           compiler-qualified guard metadata independently retains the
           concrete field mutabilities. *)
        let signature_types_match = function
          | [ IdentTypeExpr (_, None, "thread_id_t");
              PtrTypeExpr (_, ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 3)));
              PtrTypeExpr (_, ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 3)));
              ManifestTypeExpr (_, Int (Unsigned, PtrRank)) ] -> true
          | _ -> false
        in
        let declarations, definitions = List.partition_map (fun (_, decl) ->
          match decl with
          | PredFamilyDecl (loc, _, [], 0, types, Some 4, Inductiveness_Inductive) ->
              Left (loc, types)
          | PredFamilyInstanceDecl (loc, _, [], [], params, body) ->
              Right (loc, params, body)
          | _ -> invalid ()) candidates
        in
        begin match declarations, definitions with
        | [ (decl_loc, declared_types) ], [ (def_loc, params, body) ]
            when List.length candidates = 2
                && signature_types_match declared_types
                && signature_types_match (List.map fst params)
                && List.map snd params = [ "t"; "src"; "dst"; "len" ] ->
            let guard_file = match guard with Some adt_def -> loc_source_file adt_def.loc | None -> None in
            let body_is_nonempty = match body with EmpAsn _ -> false | _ -> true in
            if not body_is_nonempty || guard_file = None
                || loc_source_file decl_loc <> guard_file
                || loc_source_file def_loc <> guard_file
            then invalid ();
            Some effect_name
        | _ -> invalid ()
        end
      end

  let gen_drop_contract adt_defs self_ty self_ty_targs self_lft_args drop_effect_opt limpl =
    let outlives_clauses = [] in
    let open Ast in
    let ({ loc = ls; tparams; lft_params; fds_no_zst } : Mir.adt_def_tr) =
      List.find
        (function ({ name } : Mir.adt_def_tr) -> name = self_ty)
        adt_defs
    in
    (* TODO: Eliminate code duplication between gen_contract and gen_drop_contract *)
    let bind_pat_b n = VarPat (limpl, n) in
    let lit_pat_b n = LitPat (Var (limpl, n)) in
    (* Todo @Nima: Move RustBelt token, etc. constructors like the following to the RustBelt module so
       The hard-coded names will be in the same place and the code will be reusable *)
    let nonatomic_token_b pat =
      CallExpr
        ( limpl,
          "thread_token",
          [] (*type arguments*),
          [] (*indices*),
          [ pat ] (*arguments*),
          Static )
    in
    let thread_id_name = "_t" in
    let pre_na_token =
      Sep
        ( limpl,
          nonatomic_token_b (bind_pat_b thread_id_name),
          Operation
            (limpl, Eq, [ Var (limpl, "_t"); Var (limpl, "currentThread") ]) )
    in
    let post_na_token = nonatomic_token_b (lit_pat_b thread_id_name) in
    let lft_token_b q_pat_b n =
      let coef_n = "_q_" ^ n in
      CoefAsn
        ( limpl,
          q_pat_b coef_n,
          CallExpr
            ( limpl,
              "lifetime_token",
              [] (*type arguments*),
              [] (*indices*),
              [ LitPat (Rust_parser.expr_of_lft_param limpl ("'" ^ n)) ]
              (*arguments*),
              Static ) )
    in
    let pre_lft_tks =
      List.map (fun lft_var -> lft_token_b bind_pat_b lft_var) self_lft_args
    in
    let outlives_asns =
      outlives_clauses
      |> List.map @@ fun (r1, r2) ->
         Operation
           ( limpl,
             Eq,
             [
               CallExpr
                 ( limpl,
                   "lifetime_inclusion",
                   [],
                   [],
                   [
                     LitPat (Rust_parser.expr_of_lft_param limpl r2);
                     LitPat (Rust_parser.expr_of_lft_param limpl r1);
                   ],
                   Static );
               True limpl;
             ] )
    in
    let pre_lft_tks = pre_lft_tks @ outlives_asns in
    let post_lft_tks =
      List.map (fun lft_var -> lft_token_b lit_pat_b lft_var) self_lft_args
    in
    let (Some pre) =
      AstAux.list_to_sep_conj
        (( ls,
           Operation
             ( ls,
               Eq,
               [
                 CallExpr
                   ( ls,
                     "ref_origin",
                     [],
                     [],
                     [ LitPat (Var (ls, "self")) ],
                     Static );
                 Var (ls, "self");
               ] ) )
        :: List.map (fun e -> (limpl, e)) pre_lft_tks)
        (Some
           (Ast.Sep
              ( ls,
                pre_na_token,
                Ast.CallExpr
                  ( ls,
                    self_ty ^ "_full_borrow_content",
                    self_ty_targs,
                    List.map
                      (fun x -> Ast.LitPat (Var (ls, x)))
                      [ "_t"; "self" ],
                    [],
                    Static ) )))
    in
    List.iter2
      (fun targ tparam ->
        match targ with
        | Ast.IdentTypeExpr (_, None, x) when x = tparam -> ()
        | _ ->
            raise
              (Ast.StaticError
                 ( limpl,
                   "A drop function for a struct type whose type arguments are \
                    not identical to its type parameters is not yet supported",
                   None )))
      self_ty_targs (lft_params @ tparams);
    if
      self_lft_args
      <> List.map (fun x -> TrName.lft_name_without_apostrophe x) lft_params
    then
      raise
        (Ast.StaticError
           ( limpl,
             "A drop function for a struct type whose lifetime arguments are \
              not identical to its lifetime parameters is not yet supported",
             None ));
    let tid = Ast.Var (limpl, "_t") in
    let mk_fields_and_padding_post effect_opt =
      let padding_post =
        Ast.CallExpr
          ( limpl,
            padding_pred_name self_ty,
            self_ty_targs,
            [],
            [ LitPat (Var (limpl, "self")) ],
            Static )
      in
      let post_tail =
        match effect_opt with
        | None -> padding_post
        | Some effect_name ->
          Ast.Sep
            ( limpl,
              padding_post,
              Ast.CallExpr
                ( limpl,
                  effect_name,
                  [],
                  [],
                  List.map (fun name -> LitPat (Var (limpl, name)))
                    [ "_t"; "src"; "dst"; "len" ],
                  PredFamCall ) )
      in
      List.fold_right
        (fun ({ name; ty; loc } : Mir.field_def_tr) asn ->
          match
            let ty_interp = ty.interp in
            let* points_to_asn =
              ty_interp.points_to tid
                (Read (loc, Var (loc, "self"), name))
                (Some name)
            in
            let* own_asn = ty_interp.own tid (Var (loc, name)) in
            Ok
              (Ast.Sep
                 (loc, Ast.Sep (loc, points_to_asn, own_asn), asn))
          with
          | Ok asn -> asn
          | Error _ ->
            raise
              (Ast.StaticError
                 ( loc,
                   "Could not generate drop postcondition conjuncts for this field",
                   None )))
        fds_no_zst post_tail
    in
    let normal_post_tail = mk_fields_and_padding_post drop_effect_opt in
    let unwind_post_tail = mk_fields_and_padding_post None in
    let (Some post) =
      AstAux.list_to_sep_conj
        (List.map (fun e -> (limpl, e)) post_lft_tks)
        (Some (Ast.Sep (ls, post_na_token, normal_post_tail)))
    in
    let (Some unwind_post) =
      AstAux.list_to_sep_conj
        (List.map (fun e -> (limpl, e)) post_lft_tks)
        (Some (Ast.Sep (ls, post_na_token, unwind_post_tail)))
    in
    Ok (pre, Rust_parser.mk_outcome_post limpl post unwind_post)

  (** makes the mappings used for substituting the MIR level local declaration ids with names closer to variables surface name *)
  let make_var_id_name_maps (loc : Ast.loc) (vdis : Mir.var_debug_info list) =
    let make_var_id_name_entries surf_names_set id surf_name =
      match List.find_opt (fun (n, _) -> n = surf_name) surf_names_set with
      | None ->
          let surf_names_set = (surf_name, ref 0) :: surf_names_set in
          let env_entry_opt : VF0.var_debug_info option = None in
          let trs_entry : var_id_trs_entry =
            (*We will directly substitute the id with the surface name*)
            { id; internal_name = surf_name }
          in
          (env_entry_opt, trs_entry, surf_names_set)
      | Some (_, counter) ->
          (* This name is shadowed or is in a nested scope *)
          (* Todo @Nima: Ghost statements will refer to surface variable names.
             Since VeriFast does not support shadowing, shadowed variables either need to have different internal names or
             be in nested scopes. The current code is based on the former approach but it lacks substituting ghost statements variable names
             with their corresponding internal names. The alternative solution to the whole problem of shadowed variable names and scoped variable names
             is to use nested scopes which means adding nested scopes to the surface code scopes to handle shadowed names. *)
          (* Note @Nima: To support shadowing for ghost variables will be confusing for the user. example:
             ``
             let x = 42;
             //@ ghost x = 43;
             let y = x + 2;
             ``
             The third `x` refers to the first x but the code might be confusing for the user *)
          (*
          Ast.static_error loc
            (Printf.sprintf
               "This function shadows local variable name '%s'; this is not \
                yet supported in VeriFast"
               surf_name)
            None
          *)
          counter := succ !counter;
          let internal_name =
            (*TrName.tag_internal*) surf_name ^ "_" ^ string_of_int !counter
          in
          let env_entry_opt : VF0.var_debug_info option =
            (*Some { internal_name; surf_name }*) None
          in
          let trs_entry : var_id_trs_entry = { id; internal_name } in
          (env_entry_opt, trs_entry, surf_names_set)
    in
    let f_aux (env_map, trs_map, surf_names_set)
        ({ internal; surf_name } : Mir.var_debug_info) =
      match internal with
      | Mir.VdiiConstant ->
          (* Todo @Nima: We do not want to un-substitute the constant. We might just want to show the constant name and value in the Store in the future *)
          (env_map, trs_map, surf_names_set)
      | Mir.VdiiPlace { id } ->
          let env_entry_opt, trs_entry, surf_names_set =
            make_var_id_name_entries surf_names_set id surf_name
          in
          let env_map =
            match env_entry_opt with
            | None -> env_map
            | Some env_entry -> env_entry :: env_map
          in
          (env_map, trs_entry :: trs_map, surf_names_set)
    in
    let env_map, trs_map, surf_names_set =
      List.fold_left f_aux ([], [], []) vdis
    in
    ( env_map (* This will be used during the pprinting of execution states *),
      trs_map (* This will be used during the translation of variable names *)
    )

  let translate_unsafety (unsafety_cpn : UnsafetyRd.t) =
    let open UnsafetyRd in
    match get unsafety_cpn with
    | Safe -> Ok false
    | Unsafe -> Ok true
    | Undefined _ -> Error (`TrUnsafety "Unknown unsafety kind")

  let translate_hir_generic_param_name loc (is_type_param_name : bool)
      (n_cpn : HirGenericParamNameRd.t) =
    let open HirGenericParamNameRd in
    match get n_cpn with
    | Plain ident_cpn ->
        let* name, loc = translate_ident ident_cpn in
        if is_type_param_name && not (Verifast0.tparam_is_uppercase name) then
          raise
            (Ast.StaticError
               (loc, "Type parameters must start with an uppercase letter", None));
        Ok (name, loc)
    | Fresh id_cpn ->
        Ok ("'__" ^ Stdint.Uint128.to_string (CapnpAux.uint128_get id_cpn), loc)
    | Undefined _ -> Error (`TrHirGenericParamName "Unknown ParamName kind")

  let translate_hir_generic_param_kind (kind_cpn : HirGenericParamKindRd.t) =
    let open HirGenericParamKindRd in
    match get kind_cpn with
    | Lifetime -> Ok Hir.GenParamLifetime
    | Type -> Ok Hir.GenParamType
    | Const -> Ok Hir.GenParamConst
    | Undefined _ -> Error (`TrHirGenericParamKind "Unknown GenericParamKind")

  let translate_generic_param_def_kind (kind_cpn : VfMirRd.GenericParamDefKind.t) =
    let open VfMirRd.GenericParamDefKind in
    match get kind_cpn with
    | Lifetime -> Hir.GenParamLifetime
    | Type -> Hir.GenParamType
    | Const -> Hir.GenParamConst

  let translate_hir_generic_param (p_cpn : HirGenericParamRd.t) =
    let open HirGenericParamRd in
    let span_cpn = span_get p_cpn in
    let* loc = translate_span_data span_cpn in
    let kind_cpn = kind_get p_cpn in
    let* kind = translate_hir_generic_param_kind kind_cpn in
    let name_cpn = name_get p_cpn in
    let* name, name_loc =
      translate_hir_generic_param_name loc (kind = Hir.GenParamType) name_cpn
    in
    let pure_wrt_drop = pure_wrt_drop_get p_cpn in
    Ok (name, kind)

  let translate_generic_param_def (p_cpn : VfMirRd.GenericParamDef.t) =
    let open VfMirRd.GenericParamDef in
    let kind_cpn = kind_get p_cpn in
    let kind = translate_generic_param_def_kind kind_cpn in
    let name = name_get p_cpn in
    name, kind

  let translate_hir_generics (gens_cpn : HirGenericsRd.t) =
    let open HirGenericsRd in
    let params_cpn = params_get_list gens_cpn in
    let* params = ListAux.try_map translate_hir_generic_param params_cpn in
    let span_cpn = span_get gens_cpn in
    let* loc = translate_span_data span_cpn in
    Ok (params, loc)

  let translate_trait_required_fn (adt_defs : Mir.adt_def_tr list)
      (trait_name : string) (required_fn_cpn : TraitRd.RequiredFn.t) =
    let open TraitRd.RequiredFn in
    let name = name_get required_fn_cpn in
    let* loc = translate_span_data (name_span_get required_fn_cpn) in
    let* input_infos =
      inputs_get_list required_fn_cpn
      |> ListAux.try_map (fun ty_cpn -> translate_ty ty_cpn loc)
    in
    let inputs = input_infos |> List.map (fun { Mir.vf_ty } -> vf_ty) in
    let* output = translate_ty (output_get required_fn_cpn) loc in
    let ret_ty = output.vf_ty in
    let arg_names = arg_names_get_list required_fn_cpn in
    let (Some vf_param_decls) = Util.zip inputs arg_names in
    let* unsafe = translate_unsafety (unsafety_get required_fn_cpn) in
    let contract = contract_get_list required_fn_cpn in
    let* annots = ListAux.try_map translate_annotation contract in
    let annots = List.map translate_annot_to_vf_parser_inp annots in
    let* ( ( (nonghost_callers_only : bool),
             ((fn_type_clause : _ option), safetyProof),
             (pre_post : _ option),
             (terminates : bool) ),
           (assume_correct : bool) ) =
      if unsafe then Ok (VfMirAnnotParser.parse_func_contract loc annots)
      else (
        if contract <> [] then
          raise
            (Ast.StaticError
               ( loc,
                 "An explicit spec on a safe trait required function is not \
                  yet supported",
                 None ));
        let params =
          List.combine arg_names input_infos
          |> List.map (fun (arg_name, ty_info) -> (loc, arg_name, ty_info))
        in
        let result = (loc, output) in
        let* contract =
          gen_contract adt_defs loc
            (List.map TrName.lft_name_without_apostrophe
               (lifetime_params_get_list required_fn_cpn))
            [] [] [] params result
        in
        Ok ((false, (None, None), Some contract, false), false))
    in
    if assume_correct then
      Ast.static_error loc
        "assume_correct does not make sense on trait required functions" None;
    let ret_ty, pre_post =
      if Args.ignore_unwind_paths then
        (ret_ty, Option.map Rust_parser.result_spec_of_outcome_spec pre_post)
      else
        ( Ast.ConstructedTypeExpr
            (Ast.type_expr_loc ret_ty, "fn_outcome", [ ret_ty ]),
          pre_post )
    in
    let decl =
      Ast.Func
        ( loc,
          Ast.Regular,
          (*type params*) (Ast.unbounded_tparams ([ "Self" ] @ lifetime_params_get_list required_fn_cpn)),
          Some ret_ty,
          Printf.sprintf "%s::%s" trait_name name,
          vf_param_decls,
          nonghost_callers_only,
          (fn_type_clause, None),
          pre_post,
          terminates,
          None,
          (*virtual*) false,
          (*overrides*) [] )
    in
    Ok decl

  let translate_ty_alias_decl (ty_alias_cpn : VfMirStub.Reader.TyAlias.t) =
    let open VfMirStub.Reader.TyAlias in
    let def_id = def_id_get ty_alias_cpn in
    let* loc = translate_span_data (span_get ty_alias_cpn) in
    let generics = List.map translate_generic_param_def (generics_get_list ty_alias_cpn) in
    let* ty_info = translate_ty (ty_get ty_alias_cpn) loc in
    Ok (Ast.TypedefDecl (loc, ty_info.vf_ty, def_id, List.map fst generics))

  let translate_trait (adt_defs : Mir.adt_def_tr list)
      (skip_specless_fns : bool) (trait_cpn : TraitRd.t) =
    let name = TraitRd.name_get trait_cpn in
    let* required_fns =
      CapnpAux.ind_list_get_list (TraitRd.required_fns_get trait_cpn)
    in
    let required_fns =
      if skip_specless_fns then
        required_fns
        |> List.filter (fun required_fn_cpn ->
               not
                 (Capnp.Array.is_empty
                    (TraitRd.RequiredFn.contract_get required_fn_cpn)))
      else required_fns
    in
    ListAux.try_map (translate_trait_required_fn adt_defs name) required_fns

  let decode_clause (clause_cpn : D.clause) =
    match clause_cpn with
    | Outlives outlives_clause_cpn ->
        `Outlives
          (outlives_clause_cpn.region1.id, outlives_clause_cpn.region2.id)
    | Trait trait_clause_cpn ->
        let args = trait_clause_cpn.args |> List.map decode_generic_arg in
        `Trait (trait_clause_cpn.def_id, args, trait_clause_cpn.bound_regions)
    | Projection proj_clause_cpn -> `Projection proj_clause_cpn
    | _ -> `Ignored

  let string_of_clause clause =
    match clause with
    | `Outlives (r1, r2) -> Printf.sprintf "%s : %s" r1 r2
    | `Trait (name, `Type arg :: args, _) ->
        Printf.sprintf "%s : %s<%s>"
          (string_of_decoded_type arg)
          name
          (String.concat ", " (List.map string_of_generic_arg args))
    | `Ignored -> "(ignored)"
    | _ -> "(unknown)"

  let compute_sized_tparams preds =
    preds
    |> Util.flatmap (function
         | `Trait
             ( ("std::marker::Sized" | "core::marker::Sized"),
               [ `Type (`Param tparam) ], _ ) ->
             [ tparam ]
         | _ -> [])

  let compute_send_tparams preds =
    preds
    |> Util.flatmap (function
         | `Trait
             ( ("std::marker::Send" | "core::marker::Send"),
               [ `Type (`Param tparam) ], _ ) ->
             [ tparam ]
         | _ -> [])

  let compute_sync_tparams preds =
    preds
    |> Util.flatmap (function
         | `Trait
             ( ("std::marker::Sync" | "core::marker::Sync"),
               [ `Type (`Param tparam) ], _ ) ->
             [ tparam ]
         | _ -> [])

  let translate_projection_clause (loc : Ast.loc)
      (proj_clause_cpn : D.clause_projection) =
    let* assoc_type_def_id, tparam :: trait_args =
      let projection_term_cpn = proj_clause_cpn.projection_term in
      let* trait_args =
        projection_term_cpn.args
        |> ListAux.try_map (fun genarg_cpn ->
               let* arg = translate_generic_arg genarg_cpn loc in
               match arg with
               | Mir.GenArgLifetime _ -> assert false
               | Mir.GenArgType ty -> Ok ty.vf_ty
               | Mir.GenArgConst _ -> assert false)
      in
      Ok (projection_term_cpn.def_id, trait_args)
    in
    let trait_name, assoc_type_name =
      String.rindex assoc_type_def_id ':' |> fun i ->
      ( canonicalize_item_name (String.sub assoc_type_def_id 0 (i - 1)),
        String.sub assoc_type_def_id (i + 1)
          (String.length assoc_type_def_id - i - 1) )
    in
    let* rhs =
      let term = proj_clause_cpn.term in
      match term with
      | Ty ty_cpn ->
          let* ty = translate_decoded_ty ty_cpn loc in
          Ok ty.vf_ty
      | Const const_cpn -> assert false
    in
    Ok
      (Ast.ExprStmt
         (CallExpr
            ( loc,
              "#register_type_projection_equality",
              [
                ProjectionTypeExpr
                  (loc, tparam, trait_name, trait_args, assoc_type_name);
                rhs;
              ],
              [],
              [],
              Static )))

  let translate_body (body_tr_defs_ctx : body_tr_defs_ctx) (body_cpn : BodyRd.t)
      =
    let open BodyRd in
    r23_source_array3_interp_active := false;
    let is_generated_glue =
      VfMirRd.GeneratedGlue.enabled_get (generated_glue_get body_cpn) in
    (* This is a source-admission count, not a parser for annotations.  Every
       occurrence must later be replaced in a parsed ghost expression. *)
    let stack_addr_spelling = "mir_stack_addr" in
    let stack_addr_count raw =
      let width = String.length stack_addr_spelling in
      let rec count at total =
        if at + width > String.length raw then total
        else if String.sub raw at width = stack_addr_spelling then
          count (at + width) (total + 1)
        else count (at + 1) total
      in
      count 0 0
    in
    let var_id_trs_map_ref = ref [] in
    let* fn_sig_loc = translate_span_data (fn_sig_span_get body_cpn) in
    let ghost_stmts_cpn = ghost_stmts_get_list body_cpn in
    let r23_contains_substring text needle =
      let text_len = String.length text and needle_len = String.length needle in
      let rec loop i =
        i + needle_len <= text_len &&
        (String.sub text i needle_len = needle || loop (i + 1))
      in
      loop 0
    in
    let r23_body_name = TrName.translate_def_path (BodyRd.def_path_get body_cpn) in
    let r23_target_body = r23_body_name = "b2_three_from_local" ||
      String.ends_with ~suffix:"::b2_three_from_local" r23_body_name in
    let r23_has_marker = List.exists (fun annot ->
      let raw = AnnotationRd.raw_get annot in
      r23_contains_substring raw "r23_source_array_borrow_adapter")
      ghost_stmts_cpn in
    let r23_represent_let_lft_as_decl =
      Sys.getenv_opt "SMALLSORT_R23_SOURCE_ARRAY_BORROW" = Some "1" &&
      r23_target_body && r23_has_marker
    in
    let r23_is_let_lft_annotation annot =
      let raw = AnnotationRd.raw_get annot in
      let contents =
        if String.starts_with ~prefix:"//@" raw then
          String.sub raw 3 (String.length raw - 3)
        else if String.starts_with ~prefix:"/*@" raw then
          let content = String.sub raw 3 (String.length raw - 3) in
          if String.ends_with ~suffix:"@*/" content then
            String.sub content 0 (String.length content - 3)
          else content
        else ""
      in
      let contents = String.trim contents in
      String.starts_with ~prefix:"let_lft" contents &&
      String.length contents > String.length "let_lft" &&
      (contents.[String.length "let_lft"] = ' ' ||
       contents.[String.length "let_lft"] = '\t')
    in
    let r23_lifetime_decl_annots, ordinary_ghost_stmts_cpn =
      if r23_represent_let_lft_as_decl then
        List.partition r23_is_let_lft_annotation ghost_stmts_cpn
      else [], ghost_stmts_cpn
    in
    let* r23_lifetime_decl_blocks = ListAux.try_map (fun annot ->
      let* body_span = translate_span_data (BodyRd.span_get body_cpn) in
      let body_end_pos = snd (Ast.lexed_loc body_span) in
      let body_end_loc = Ast.Lexed (body_end_pos, body_end_pos) in
      let* translated = translate_annotation annot in
      let start_pos, raw = translate_annot_to_vf_parser_inp translated in
      let decl_raw =
        if String.starts_with ~prefix:"//@" raw then
          "/*@" ^ String.sub raw 3 (String.length raw - 3) ^ "@*/"
        else raw
      in
      let declarations =
        VfMirAnnotParser.parse_ghost_decl_batch (start_pos, decl_raw)
      in
      Ok (translated.span,
        Ast.BlockStmt (translated.span, declarations, [], body_end_loc, ref [])))
      r23_lifetime_decl_annots in
    let r23_lifetime_decl_locs =
      List.map fst r23_lifetime_decl_blocks in
    let stack_addr_occurrences =
      List.fold_left
        (fun total annot -> total + stack_addr_count (AnnotationRd.raw_get annot))
        0 ghost_stmts_cpn
    in
    let reject_stack_addr_in_annotation annot =
      if stack_addr_count (AnnotationRd.raw_get annot) <> 0 then
        Ast.static_error fn_sig_loc
          "mir_stack_addr is allowed only in body ghost statements and loop specifications"
          None
    in
    List.iter
      (fun block ->
        reject_stack_addr_in_annotation
          (BodyRd.GhostDeclBlock.start_get block))
      (ghost_decl_blocks_get_list body_cpn);
    List.iter reject_stack_addr_in_annotation
      (ContractRd.annotations_get_list (contract_get body_cpn));
    let* ghost_stmts = ListAux.try_map translate_ghost_stmt ordinary_ghost_stmts_cpn in
    let ghost_stmts =
      List.map (fun loc -> Ast.NoopStmt loc) r23_lifetime_decl_locs @ ghost_stmts
    in
    let* ghost_stmts =
      ListAux.try_sort LocAux.compare_err_desc
        (fun s1 s2 ->
          let f s = s |> Ast.stmt_loc |> Ast.lexed_loc in
          let l1, l2 = (f s1, f s2) in
          LocAux.try_compare_loc l1 l2)
        ghost_stmts
    in
    let* ghost_decl_blocks =
      ListAux.try_map translate_ghost_decl_block
        (ghost_decl_blocks_get_list body_cpn)
    in
    let ghost_decl_blocks =
      List.map snd r23_lifetime_decl_blocks @ ghost_decl_blocks
    in
    (* This opt-in proof CFG is supplied by three adjacent ghost annotations.
       The exporter still sees the original Rust body and its original braces. *)
    let marker_stmt name = function
      | Ast.PureStmt (_, Ast.ExprStmt (Ast.CallExpr (_, found, [Ast.IdentTypeExpr (_, None, lft)], [], [], Ast.Static)))
      | Ast.ExprStmt (Ast.CallExpr (_, found, [Ast.IdentTypeExpr (_, None, lft)], [], [], Ast.Static))
        when found = name && String.length lft > 1 && lft.[0] = '\'' -> Some lft
      | _ -> None
    in
    let block_marker name = function
      | Ast.PureStmt (l, Ast.BlockStmt (_, [], head :: commands, close, _)) ->
          (match marker_stmt name head with
           | Some lft -> Some (l, close, lft, commands)
           | None -> None)
      | _ -> None
    in
    let r23_adapter_marker name stmt =
      let unpure = function Ast.PureStmt (_, inner) -> inner | stmt -> stmt in
      match unpure stmt with
      | Ast.BlockStmt (_, [], head :: commands, close, _) ->
          let head = unpure head in
          (match head with
           | Ast.ExprStmt
               (Ast.CallExpr (_, found, [], [], args, Ast.Static))
             when found = name -> Some (Ast.stmt_loc stmt, close, args, commands)
           | _ -> None)
      | Ast.ExprStmt
          (Ast.CallExpr (_, found, [], [], args, Ast.Static))
        when found = name ->
          let slot_loc = Ast.stmt_loc stmt in
          Some (slot_loc, slot_loc, args, [])
      | _ -> None
    in
    let r23_raw_marker_call name stmt =
      let unpure = function Ast.PureStmt (_, inner) -> inner | stmt -> stmt in
      let is_call = function
        | Ast.ExprStmt (Ast.CallExpr (_, found, _, _, _, Ast.Static))
          -> found = name
        | _ -> false in
      match unpure stmt with
      | Ast.BlockStmt (_, _, head :: _, _, _) -> is_call (unpure head)
      | other -> is_call other
    in
    let r23_pre_marker_vars = function
      | [Ast.LitPat (Ast.Var (_, token)); Ast.LitPat (Ast.Var (_, values))] ->
          Some (token, values)
      | _ -> None
    in
    let r23_post_marker_vars = function
      | [Ast.LitPat (Ast.Var (_, token)); Ast.LitPat (Ast.Var (_, values));
         Ast.LitPat (Ast.Var (_, begin_local)); Ast.LitPat (Ast.Var (_, state))] ->
          Some (token, values, begin_local, state)
      | _ -> None
    in
    let marked name = List.filter_map (block_marker name) ghost_stmts in
    let r23_pre_markers =
      List.filter_map (r23_adapter_marker "r23_source_array_borrow_adapter")
        ghost_stmts
    in
    let r23_post_markers =
      List.filter_map (r23_adapter_marker "r23_source_array_borrow_adapter_end")
        ghost_stmts
    in
    let r23_source_adapter_enabled =
      Sys.getenv_opt "SMALLSORT_R23_SOURCE_ARRAY_BORROW" = Some "1"
    in
    let r23_source_array_adapter =
      match r23_pre_markers, r23_post_markers with
      | [], [] ->
          if List.exists (r23_raw_marker_call "r23_source_array_borrow_adapter") ghost_stmts ||
             List.exists (r23_raw_marker_call "r23_source_array_borrow_adapter_end") ghost_stmts
          then Ast.static_error fn_sig_loc
            "Malformed R23 source array adapter marker" None
          else None
      | [pre_loc, pre_end, pre_args, pre_commands],
        [post_loc, post_end, post_args, post_commands] ->
          let fail loc reason =
            Ast.static_error loc
              ("R23 source array adapter marker refused: " ^ reason) None
          in
          if not r23_source_adapter_enabled then
            fail pre_loc "the explicit R23 source-adapter opt-in is disabled";
          if TranslatorArgs.ignore_unwind_paths then
            fail pre_loc "the R23 source adapter requires checked unwind outcomes";
          let body_name = TrName.translate_def_path (def_path_get body_cpn) in
          if not (body_name = "b2_three_from_local" ||
                  String.ends_with ~suffix:"::b2_three_from_local" body_name)
          then fail pre_loc "marker outside b2_three_from_local";
          let token, values = match r23_pre_marker_vars pre_args with
            | Some args -> args
            | None -> fail pre_loc "pre marker argument shape mismatch" in
          let post_token, post_values, begin_local, values_state =
            match r23_post_marker_vars post_args with
            | Some args -> args
            | None -> fail post_loc "post marker argument shape mismatch" in
          let ((pre_file, pre_line, _), _) = Ast.lexed_loc pre_loc in
          let ((pre_end_file, pre_end_line, _), _) = Ast.lexed_loc pre_end in
          let ((post_file, post_line, _), _) = Ast.lexed_loc post_loc in
          let ((post_end_file, post_end_line, _), _) = Ast.lexed_loc post_end in
          if token <> "r23_borrow_k" || post_token <> token ||
             values <> "values" || post_values <> values ||
             begin_local <> "begin" || values_state <> "r23_borrow_values" then
            fail pre_loc "marker binders do not match the canonical source site";
          if pre_file <> pre_end_file || pre_file <> post_file ||
             pre_file <> post_end_file || pre_line >= post_line ||
             pre_end_line > post_line || post_end_line < post_line then
            fail pre_loc "markers are not ordered in one source file";
          let source_pos loc = fst (Ast.lexed_loc loc) in
          let pre_pos = source_pos pre_loc in
          let post_pos = source_pos post_loc in
          List.iter (fun decl_loc ->
            let decl_start, decl_end = Ast.lexed_loc decl_loc in
            let (decl_file, _, _) = decl_start in
            let (decl_end_file, _, _) = decl_end in
            if decl_file <> pre_file || decl_end_file <> post_file ||
               decl_start <= pre_pos || decl_start >= post_pos ||
               decl_end > post_pos
            then fail decl_loc
              "R23 let_lft declaration must be between the exact source markers")
            r23_lifetime_decl_locs;
          if pre_commands <> [] || post_commands <> [] then
            fail pre_loc "R23 line markers must be zero-authority single statements";
          let unpure = function
            | Ast.PureStmt (_, stmt) -> stmt
            | stmt -> stmt in
          let direct_call = function
            | Ast.ExprStmt (Ast.CallExpr (_, name, _, _, args, Ast.Static)) ->
                Some (name, args)
            | _ -> None in
          let direct_calls commands = List.filter_map
            (fun stmt -> direct_call (unpure stmt)) commands in
          let source_loc stmt = fst (Ast.lexed_loc (Ast.stmt_loc stmt)) in
          let (pre_pos_file, pre_pos_line, _) = fst (Ast.lexed_loc pre_loc) in
          let (post_pos_file, post_pos_line, _) = fst (Ast.lexed_loc post_loc) in
          let is_extracted_lifetime_noop = function
            | Ast.NoopStmt loc -> List.mem loc r23_lifetime_decl_locs
            | _ -> false in
          let pre_source_commands = List.filter (fun stmt ->
            let (file, line, _) = source_loc stmt in
            file = pre_pos_file && file = post_pos_file &&
            pre_pos_line < line && line < post_pos_line &&
            not (is_extracted_lifetime_noop stmt))
              ghost_stmts in
          let rec take_post_commands acc = function
            | [] -> fail post_loc "post annotation sequence lacks Array_to_array"
            | stmt :: rest ->
                let acc = acc @ [stmt] in
                (match direct_call (unpure stmt) with
                 | Some ("Array_to_array", _) -> acc
                 | _ -> take_post_commands acc rest)
          in
          let post_candidates = List.filter (fun stmt ->
            let (file, line, _) = source_loc stmt in
            file = post_pos_file && line > post_pos_line) ghost_stmts in
          let post_source_commands = take_post_commands [] post_candidates in
          let calls_are expected commands =
            List.map fst (direct_calls commands) = expected in
          let annotation_shape stmt =
            match unpure stmt with
            | Ast.DeclStmt (_, declarations) ->
                (match declarations with
                 | [(_, _, name, _, _)] -> "decl:" ^ name
                 | _ -> "decl:multiple")
            | Ast.Assert _ -> "assert"
            | Ast.Open (_, _, name, _, _, _, _) -> "open:" ^ name
            | Ast.Close (_, _, name, _, _, _, _) -> "close:" ^ name
            | Ast.ExprStmt (Ast.CallExpr (_, name, _, _, _, Ast.Static)) ->
                "call:" ^ name
            | _ -> "other"
          in
          let pre_shape = List.map annotation_shape pre_source_commands in
          let post_shape = List.map annotation_shape post_source_commands in
          if pre_shape <>
             ["decl:r23_array_p"; "assert"; "call:array_to_Array";
              "assert"; "call:r9_make_u64_owners";
              "close:r23_u64_array3_own"; "close:r23_u64_array3_fbc";
              "call:borrow"] then
            fail pre_loc "pre annotations differ from the exact checked array3 ownership sequence";
          if post_shape <>
             ["call:end_lifetime"; "call:borrow_end";
              "call:r23_dispose_dead_array3_borrow";
              "open:r23_u64_array3_fbc"; "assert";
              "open:r23_u64_array3_own"; "call:r9_drop_u64_owners";
              "call:Array_to_array"] then
            fail post_loc "post annotations differ from the exact checked physical owner restoration sequence";
          if not (calls_are ["array_to_Array"; "r9_make_u64_owners"; "borrow"]
                    pre_source_commands) then
            fail pre_loc "pre annotation sequence is not the exact checked array owner and borrow setup";
          if not (calls_are ["end_lifetime"; "borrow_end";
                              "r23_dispose_dead_array3_borrow";
                              "r9_drop_u64_owners"; "Array_to_array"]
                    post_source_commands) then
            fail post_loc "post annotation sequence is not the exact checked borrow and owner restoration";
          let is_fbc_arg = function
            | Ast.LitPat
                (Ast.CallExpr (_, "r23_u64_array3_fbc", [], [],
                  [Ast.LitPat (Ast.Var (_, "t"));
                   Ast.LitPat (Ast.Var (_, "r23_array_p"))], Ast.Static)) -> true
            | _ -> false in
          let pre_protocol = direct_calls pre_source_commands |> List.filter
            (fun (name, _) -> name = "borrow") in
          let post_protocol = direct_calls post_source_commands |> List.filter
            (fun (name, _) -> name = "end_lifetime" || name = "borrow_end") in
          (match pre_protocol with
           | [("borrow", [Ast.LitPat (Ast.Var (_, found)); p])]
             when found = token && is_fbc_arg p -> ()
           | _ -> fail pre_loc
               "pre marker must borrow the exact r23 array3 full-borrow content");
          (match post_protocol with
           | [("end_lifetime", [Ast.LitPat (Ast.Var (_, found1))]);
              ("borrow_end", [Ast.LitPat (Ast.Var (_, found2)); p])]
             when found1 = token && found2 = token && is_fbc_arg p -> ()
           | _ -> fail post_loc
               "post marker must end and restore the same r23 array3 full-borrow content");
          let source_lft_name = "'r23_borrow" in
          let source_lifetime_decl_count =
            List.fold_left (fun count -> function
              | Ast.BlockStmt (_, decls, _, _, _) ->
                  count + List.length (List.filter (function
                    | Ast.TypeWithTypeidDecl _ -> true
                    | _ -> false) decls)
              | _ -> count) 0 ghost_decl_blocks
          in
          if source_lifetime_decl_count <> 1 then
            fail pre_loc
              "R23 source adapter requires exactly one source let_lft declaration";
          let has_lft_binding =
            List.exists (function
              | Ast.BlockStmt (_, decls, _, _, _) ->
                  List.exists (function
                    | Ast.TypeWithTypeidDecl (_, name,
                        Ast.CallExpr (_, "typeid_of_lft", [], [],
                          [Ast.LitPat (Ast.Var (_, found))], Ast.Static))
                      -> name = source_lft_name && found = token
                    | _ -> false) decls
              | _ -> false) ghost_decl_blocks
          in
          if not has_lft_binding then
            fail pre_loc "missing explicit let_lft 'r23_borrow = r23_borrow_k binding";
          let is_begin_lifetime = function
            | Ast.CallExpr (_, "begin_lifetime", [], [], [], Ast.Static) -> true
            | _ -> false in
          let fresh_token_decls = List.filter_map (function
            | Ast.DeclStmt (loc, [(_, None, name, Some init, _)])
            | Ast.PureStmt (loc, Ast.DeclStmt (_, [(_, None, name, Some init, _)]))
              when name = token && is_begin_lifetime init -> Some loc
            | _ -> None) ghost_stmts in
          let token_precedes_marker loc =
            let ((token_file, token_line, _), _) = Ast.lexed_loc loc in
            let ((marker_file, marker_line, _), _) = Ast.lexed_loc pre_loc in
            token_file = marker_file && token_line < marker_line in
          (match fresh_token_decls with
           | [loc] when token_precedes_marker loc -> ()
           | [_] -> fail pre_loc
               "begin_lifetime token is not declared before the source adapter marker"
           | [] -> fail pre_loc
               "source adapter lifetime token is not the result of begin_lifetime"
           | _ -> fail pre_loc
               "source adapter lifetime token has multiple begin_lifetime declarations");
          Some
            { r23_pre_marker_loc = pre_loc;
              r23_pre_marker_end = pre_end;
              r23_post_marker_loc = post_loc;
              r23_post_marker_end = post_end;
              r23_pre_stmt = Ast.NoopStmt pre_loc;
              r23_post_stmt = Ast.PureStmt (post_loc,
                Ast.BlockStmt (post_loc, [], post_source_commands,
                  (Ast.stmt_loc (List.hd (List.rev post_source_commands))), ref []));
              r23_lifetime_token = token;
              r23_values_local = values;
              r23_begin_local = begin_local;
              r23_values_state = values_state;
              r23_ref_local = None;
              r23_unsize_local = None;
              r23_ref_seen = false;
              r23_unsize_seen = false;
              r23_call_seen = false;
              r23_projection_approved = false;
              r23_checked_helper_name = None;
              r23_scoped_local_decls = [];
              r23_scope_decls_inserted = false;
              r23_unwind_epilogue = None;
              r23_unwind_label = "#merge_r23_source_borrow_unwind" }
      | (loc, _, _, _) :: _, _ | _, (loc, _, _, _) :: _ ->
          Ast.static_error loc
            "R23 source array adapter requires exactly one pre/post marker pair"
            None
    in
    let* r23_source_array_adapter =
      match r23_source_array_adapter with
      | None -> Ok None
      | Some plan ->
          let refuse loc why =
            Ast.static_error loc
              ("R23 source array adapter MIR binding refused: " ^ why) None
          in
          let place_local place =
            if PlaceRd.projection_get_list place <> [] then None
            else Some (LocalDeclIdRd.name_get (PlaceRd.local_get place))
          in
          let source_local_id surf_name =
            let ids = List.filter_map (fun vdi ->
              if translate_symbol (VarDebugInfoRd.name_get vdi) <> surf_name then None
              else match VarDebugInfoContentsRd.get
                  (VarDebugInfoRd.value_get vdi) with
                | VarDebugInfoContentsRd.Place place -> place_local place
                | _ -> None)
              (var_debug_info_get_list body_cpn)
              |> List.sort_uniq String.compare in
            match ids with
            | [id] -> id
            | [] -> refuse plan.r23_pre_marker_loc
                ("source local has no unique MIR binding: " ^ surf_name)
            | _ -> refuse plan.r23_pre_marker_loc
                ("source local has ambiguous MIR bindings: " ^ surf_name)
          in
          let values_id = source_local_id plan.r23_values_local in
          let begin_id = source_local_id plan.r23_begin_local in
          let is_u64_array3_ty ty_cpn loc =
            match TyKindRd.get (TyRd.kind_get ty_cpn) with
            | TyKindRd.Array array_ty ->
                if decode_ty (D.decode_ty (ArrayTyRd.elem_ty_get array_ty))
                   <> `Uint D.U64
                then Ok false
                else
                  let* len_expr = translate_ty_const
                    (D.decode_ty_const (ArrayTyRd.size_get array_ty)) loc in
                  (match len_expr with
                   | Ast.CastExpr (_, _, Ast.IntLit (_, n, _, _, _))
                   | Ast.IntLit (_, n, _, _, _) ->
                       Ok (Big_int.compare_big_int n
                         (Big_int.big_int_of_int 3) = 0)
                   | _ -> Ok false)
            | _ -> Ok false
          in
          let local_decl_ty local_id =
            List.find_opt (fun decl ->
              LocalDeclIdRd.name_get (LocalDeclRd.id_get decl) = local_id)
              (local_decls_get_list body_cpn)
          in
          let* values_is_array3 =
            match local_decl_ty values_id with
            | Some decl -> is_u64_array3_ty
                (LocalDeclRd.ty_get decl) plan.r23_pre_marker_loc
            | None -> refuse plan.r23_pre_marker_loc
                "array local declaration is absent"
          in
          if not values_is_array3 then
            refuse plan.r23_pre_marker_loc
              "marked local is not exactly [u64; 3]";
          let operand_local op =
            match OperandRd.get op with
            | OperandRd.Copy place | OperandRd.Move place -> place_local place
            | _ -> None
          in
          let array3_refs = ref [] in
          let unsize_casts = ref [] in
          let assign_records = ref [] in
          let analyze_stmt stmt =
            match StatementKindRd.get (StatementRd.kind_get stmt) with
            | StatementKindRd.Assign data ->
                let lhs = place_local
                  (StatementKindRd.AssignData.lhs_place_get data) in
                let rhs = StatementKindRd.AssignData.rhs_rvalue_get data in
                assign_records :=
                  (StatementKindRd.AssignData.lhs_place_get data, rhs, stmt)
                  :: !assign_records;
                (match lhs, RvalueRd.get rhs with
                 | Some dst, RvalueRd.Ref ref_data ->
                     let source = place_local (RefDataRd.place_get ref_data) in
                     let is_mut = match RefBorrowKindRd.get
                         (RefDataRd.bor_kind_get ref_data) with
                       | RefBorrowKindRd.Mut -> true
                       | _ -> false in
                     let* is_array3 = is_u64_array3_ty
                       (RefDataRd.place_ty_get ref_data)
                       plan.r23_pre_marker_loc in
                     if source = Some values_id && is_mut && is_array3 then
                       array3_refs := (dst, ref_data, stmt) :: !array3_refs;
                     Ok ()
                 | Some dst, RvalueRd.Cast cast_data ->
                     let cast_source = match OptionRd.get
                         (CastDataRd.source_ty_get cast_data) with
                       | OptionRd.Something ptr -> Some (VfMirRd.of_pointer ptr)
                       | _ -> None in
                     let target_ty = CastDataRd.ty_get cast_data in
                     let source_ref_is_array3 = match cast_source with
                       | Some ty ->
                           (match decode_ty (D.decode_ty ty) with
                            | `Ref (_, true, `Array) -> true
                            | _ -> false)
                       | None -> false in
                     let target_ref_is_u64_slice =
                       match decode_ty (D.decode_ty target_ty) with
                       | `Ref (_, true, `Slice (`Uint D.U64)) -> true
                       | _ -> false in
                     let pointer_coercion =
                       match CastKindRd.get (CastDataRd.kind_get cast_data) with
                       | CastKindRd.PointerCoercion -> true
                       | _ -> false in
                     let unsize = match OptionRd.get
                         (CastDataRd.pointer_coercion_data_get cast_data) with
                       | OptionRd.Something ptr ->
                           let data = VfMirRd.of_pointer ptr in
                           let kind_is_unsize = match PointerCoercionKindRd.get
                               (PointerCoercionDataRd.kind_get data) with
                             | PointerCoercionKindRd.Unsize -> true
                             | _ -> false in
                           let source_is_implicit = match PointerCoercionSourceRd.get
                               (PointerCoercionDataRd.coercion_source_get data) with
                             | PointerCoercionSourceRd.Implicit -> true
                             | _ -> false in
                           pointer_coercion && kind_is_unsize && source_is_implicit
                       | _ -> false in
                     (match source_ref_is_array3, target_ref_is_u64_slice,
                            unsize, operand_local
                              (CastDataRd.operand_get cast_data) with
                      | true, true, true, Some src ->
                          let* source_is_array3 = match cast_source with
                            | Some ty -> is_u64_array3_ty
                                (match TyKindRd.get (TyRd.kind_get ty) with
                                 | TyKindRd.Ref ref_ty -> RefTyRd.ty_get ref_ty
                                 | _ -> ty)
                                plan.r23_pre_marker_loc
                            | None -> Ok false in
                          if source_is_array3 then
                            unsize_casts := (src, dst, cast_data, stmt)
                              :: !unsize_casts;
                          Ok ()
                      | _ -> Ok ())
                 | _ -> Ok ())
            | _ -> Ok ()
          in
          let* _ = ListAux.try_map analyze_stmt
            (List.concat_map BasicBlockRd.statements_get_list
              (basic_blocks_get_list body_cpn)) in
          let ref_dst, ref_data, ref_stmt = match !array3_refs with
            | [one] -> one
            | [] -> refuse plan.r23_pre_marker_loc
                "no unique mutable Ref of the marked array local"
            | _ -> refuse plan.r23_pre_marker_loc
                "multiple mutable Ref candidates for the marked array local"
          in
          let cast_data, cast_dst, cast_stmt = match
              List.filter_map (fun (src, dst, data, stmt) ->
                if src = ref_dst then Some (data, dst, stmt) else None)
              !unsize_casts with
            | [one] -> one
            | [] -> refuse plan.r23_pre_marker_loc
                "no unique exact Unsize cast consumes the mutable array Ref"
            | _ -> refuse plan.r23_pre_marker_loc
                "multiple Unsize casts consume the mutable array Ref"
          in
          let ref_local_ty = match local_decl_ty ref_dst with
            | Some decl -> Some (LocalDeclRd.ty_get decl)
            | None -> None in
          let cast_local_ty = match local_decl_ty cast_dst with
            | Some decl -> Some (LocalDeclRd.ty_get decl)
            | None -> None in
          let* ref_local_is_array3 = match ref_local_ty with
            | Some ty ->
                (match decode_ty (D.decode_ty ty),
                       TyKindRd.get (TyRd.kind_get ty) with
                 | `Ref (_, true, `Array), TyKindRd.Ref ref_ty ->
                     is_u64_array3_ty (RefTyRd.ty_get ref_ty)
                       plan.r23_pre_marker_loc
                 | _ -> Ok false)
            | None -> Ok false in
          let cast_local_is_slice = match cast_local_ty with
            | Some ty ->
                (match decode_ty (D.decode_ty ty) with
                 | `Ref (_, true, `Slice (`Uint D.U64)) -> true
                 | _ -> false)
            | None -> false in
          if not ref_local_is_array3 || not cast_local_is_slice then
            refuse plan.r23_pre_marker_loc
              "reference temporary local declarations disagree with Ref/Unsize types";
          let region_identity region =
            match OptionRd.get (RegionRd.identity_get region) with
            | OptionRd.Something ptr ->
                let identity = VfMirRd.of_pointer ptr in
                (match RegionIdentityRd.get identity with
                 | RegionIdentityRd.InferenceVariable variable ->
                     Some
                       ( RegionInferenceVariableRd.scope_id_get variable,
                         Stdint.Uint32.to_string
                           (RegionInferenceVariableRd.variable_id_get variable) )
                 | RegionIdentityRd.Erased _ -> None)
            | _ -> None
          in
          let ty_region ty =
            match TyKindRd.get (TyRd.kind_get ty) with
            | TyKindRd.Ref ref_ty -> Some (RefTyRd.region_get ref_ty)
            | _ -> None
          in
          let cast_source_ty = match OptionRd.get
              (CastDataRd.source_ty_get cast_data) with
            | OptionRd.Something ptr -> Some (VfMirRd.of_pointer ptr)
            | _ -> None in
          let cast_target_ty = CastDataRd.ty_get cast_data in
          let all_region_identities =
            [ Some (region_identity (RefDataRd.region_get ref_data));
              (match cast_source_ty with
               | Some ty -> Option.map region_identity (ty_region ty)
               | None -> None);
              Option.map region_identity (ty_region cast_target_ty) ]
            |> List.filter_map (fun x -> x)
          in
          let typed_region_identities = List.filter_map (fun x -> x) all_region_identities in
          let body_region_scope = BodyRd.region_scope_id_get body_cpn in
          (match typed_region_identities with
           | [] -> () (* Erased/absent compiler identity: the explicit unique source scope is used. *)
           | (scope, variable) :: rest ->
               if scope = "" || scope <> body_region_scope ||
                  List.length typed_region_identities <> List.length all_region_identities ||
                  not (List.for_all (fun (scope', variable') ->
                    scope' = scope && variable' = variable) rest) then
                 refuse plan.r23_pre_marker_loc
                   "typed MIR region identities are missing, cross-scope, or inconsistent");
          if ref_dst = cast_dst || cast_dst = values_id then
            refuse plan.r23_pre_marker_loc "reference temporaries alias source places";
          let ref_uses = ref 0 and cast_uses = ref 0 in
          let rooted_local place =
            Some (LocalDeclIdRd.name_get (PlaceRd.local_get place)) in
          let count_place id place =
            if rooted_local place = Some id then
              incr (if id = ref_dst then ref_uses else cast_uses)
          in
          let count_operand id operand =
            match OperandRd.get operand with
            | OperandRd.Copy place | OperandRd.Move place -> count_place id place
            | OperandRd.Constant _ -> ()
          in
          List.iter (fun (lhs, rv, _) ->
            (* These are temporary references: any overwrite or projected
               place use is an escape/ambiguity, just like an extra copy. *)
            let lhs_root = rooted_local lhs in
            let is_ref_definition = lhs_root = Some ref_dst &&
              (match RvalueRd.get rv with RvalueRd.Ref _ -> true | _ -> false) in
            let is_cast_definition = lhs_root = Some cast_dst &&
              (match RvalueRd.get rv with RvalueRd.Cast _ -> true | _ -> false) in
            if lhs_root = Some ref_dst && not is_ref_definition then incr ref_uses;
            if lhs_root = Some cast_dst && not is_cast_definition then incr cast_uses;
            let count = count_operand in
            match RvalueRd.get rv with
            | RvalueRd.Use op -> count ref_dst op; count cast_dst op
            | RvalueRd.Repeat data ->
                count ref_dst (RvalueRd.RepeatData.operand_get data);
                count cast_dst (RvalueRd.RepeatData.operand_get data)
            | RvalueRd.Ref data ->
                count_place ref_dst (RefDataRd.place_get data);
                count_place cast_dst (RefDataRd.place_get data)
            | RvalueRd.RawPtr data ->
                count_place ref_dst (RawPtrDataRd.place_get data);
                count_place cast_dst (RawPtrDataRd.place_get data)
            | RvalueRd.Cast data ->
                count ref_dst (CastDataRd.operand_get data);
                count cast_dst (CastDataRd.operand_get data)
            | RvalueRd.BinaryOp data ->
                let l = RvalueRd.BinaryOpData.operandl_get data
                and r = RvalueRd.BinaryOpData.operandr_get data in
                List.iter (count ref_dst) [l; r];
                List.iter (count cast_dst) [l; r]
            | RvalueRd.UnaryOp data ->
                count ref_dst (RvalueRd.UnaryOpData.operand_get data);
                count cast_dst (RvalueRd.UnaryOpData.operand_get data)
            | RvalueRd.Aggregate data ->
                List.iter (count ref_dst)
                  (AggregateDataRd.operands_get_list data);
                List.iter (count cast_dst)
                  (AggregateDataRd.operands_get_list data)
            | RvalueRd.Discriminant data ->
                count_place ref_dst (DiscriminantDataRd.place_get data);
                count_place cast_dst (DiscriminantDataRd.place_get data)
            | RvalueRd.ThreadLocalRef -> ()) !assign_records;
          List.iter (fun stmt ->
            match StatementKindRd.get (StatementRd.kind_get stmt) with
            | StatementKindRd.PlaceMention place ->
                count_place ref_dst place;
                count_place cast_dst place
            | StatementKindRd.Assume operand ->
                count_operand ref_dst operand;
                count_operand cast_dst operand
            | _ -> ())
            (List.concat_map BasicBlockRd.statements_get_list
              (basic_blocks_get_list body_cpn));
          let method_calls = ref [] in
          List.iter (fun block ->
            match TerminatorKindRd.get
                (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
            | TerminatorKindRd.Call call ->
                let method_name = match D.decode_operand
                    (FnCallDataRd.func_get call) with
                  | Constant {const = Val {ty = {kind = FnDef {id = {name}; _}}}} ->
                      canonicalize_item_name name
                  | _ -> "" in
                if method_name = "std::slice::<impl [T]>::as_mut_ptr" then
                  method_calls := (call, block) :: !method_calls
            | _ -> ()) (basic_blocks_get_list body_cpn);
          let call, _call_block = match !method_calls with
            | [one] -> one
            | [] -> refuse plan.r23_pre_marker_loc
                "the marked source site has no slice::as_mut_ptr terminator"
            | _ -> refuse plan.r23_pre_marker_loc
                "the body has multiple slice::as_mut_ptr terminators"
          in
          let helper_body = match body_tr_defs_ctx.r23_checked_slice_helper with
            | Some body -> body
            | None -> refuse plan.r23_pre_marker_loc
                "the exported unit has no unique checked r23 slice helper body"
          in
          let projection = match OptionRd.get
              (FnCallDataRd.r23_slice_projection_get call) with
            | OptionRd.Something ptr -> ptr
            | _ -> refuse plan.r23_pre_marker_loc
                "the selected std call has no actual callee MIR projection"
          in
          let checked_helper_name = r23_verify_checked_slice_helper
            plan.r23_pre_marker_loc projection helper_body in
          plan.r23_checked_helper_name <- Some checked_helper_name;
          plan.r23_projection_approved <- true;
          (match OptionRd.get (FnCallDataRd.target_get call) with
           | OptionRd.Something _ -> ()
           | _ -> refuse plan.r23_pre_marker_loc
               "as_mut_ptr call has no original normal successor");
          List.iter (fun block ->
            let terminator = BasicBlockRd.terminator_get block in
            match TerminatorKindRd.get (TerminatorRd.kind_get terminator) with
            | TerminatorKindRd.Call data ->
                count_operand ref_dst (FnCallDataRd.func_get data);
                count_operand cast_dst (FnCallDataRd.func_get data);
                List.iter (count_operand ref_dst)
                  (FnCallDataRd.args_get_list data);
                List.iter (count_operand cast_dst)
                  (FnCallDataRd.args_get_list data)
            | TerminatorKindRd.SwitchInt data ->
                count_operand ref_dst (SwitchIntDataRd.discr_get data);
                count_operand cast_dst (SwitchIntDataRd.discr_get data)
            | TerminatorKindRd.Drop data ->
                count_place ref_dst (DropDataRd.place_get data);
                count_place cast_dst (DropDataRd.place_get data)
            | TerminatorKindRd.Assert data ->
                count_operand ref_dst (AssertDataRd.cond_get data);
                count_operand cast_dst (AssertDataRd.cond_get data)
            | _ -> ()) (basic_blocks_get_list body_cpn);
          let call_args = FnCallDataRd.args_get_list call in
          let receiver_id = match call_args with
            | [receiver] -> operand_local receiver
            | _ -> None in
          if receiver_id <> Some cast_dst then
            refuse plan.r23_pre_marker_loc
              "as_mut_ptr receiver is not the exact Unsize result";
          let destination_id = place_local (FnCallDataRd.destination_get call) in
          if destination_id <> Some begin_id then
            refuse plan.r23_pre_marker_loc
              "as_mut_ptr destination is not the marked begin local";
          if !ref_uses <> 1 || !cast_uses <> 1 then
            refuse plan.r23_pre_marker_loc
              "a reference temporary has an extra use or escapes the exact chain";
          let* ref_span = translate_span_data
            (SourceInfoRd.span_get (StatementRd.source_info_get ref_stmt)) in
          let* cast_span = translate_span_data
            (SourceInfoRd.span_get (StatementRd.source_info_get cast_stmt)) in
          let* call_span = translate_span_data (FnCallDataRd.call_span_get call) in
          let ((marker_file, marker_line, _), _) =
            Ast.lexed_loc plan.r23_pre_marker_loc in
          let ((post_file, post_line, _), _) =
            Ast.lexed_loc plan.r23_post_marker_loc in
          let in_marker_range loc =
            let ((file, line, _), _) = Ast.lexed_loc loc in
            file = marker_file && file = post_file &&
            marker_line < line && line < post_line
          in
          if not (in_marker_range ref_span && in_marker_range cast_span &&
                  in_marker_range call_span) then
            refuse plan.r23_pre_marker_loc
              "Ref, Unsize, and as_mut_ptr spans do not lie between the markers";
          let source_point loc = fst (Ast.lexed_loc loc) in
          let ref_file, ref_line, ref_col = source_point ref_span
          and cast_file, cast_line, cast_col = source_point cast_span
          and call_file, call_line, call_col = source_point call_span in
          if ref_file <> cast_file || ref_file <> call_file ||
             (ref_line, ref_col) > (cast_line, cast_col) ||
             (cast_line, cast_col) > (call_line, call_col) then
            refuse plan.r23_pre_marker_loc
              "Ref, Unsize, and as_mut_ptr are not ordered at one original source site";
          let _ = ref_data and _ = cast_data and _ = ref_dst in
          plan.r23_ref_local <- Some ref_dst;
          plan.r23_unsize_local <- Some cast_dst;
          Ok (Some plan)
    in
    r23_source_array3_interp_active := r23_source_array_adapter <> None;
    let r9_return_marker_stmt = function
      | Ast.PureStmt (_, Ast.ExprStmt (Ast.CallExpr (_, "guard_current_return_recover", [], [], [], Ast.Static)))
      | Ast.ExprStmt (Ast.CallExpr (_, "guard_current_return_recover", [], [], [], Ast.Static)) -> true
      | _ -> false
    in
    let r9_unpure = function Ast.PureStmt (_, stmt) -> stmt | stmt -> stmt in
    let r9_array_u64_open = function
      | Ast.Open (_, _, "array",
          [Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3))],
          _, _, _) -> true
      | _ -> false
    in
    let r9_array_u64_close = function
      | Ast.Close (_, None, "array",
          [Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3))],
          [], [_; Ast.LitPat _; Ast.LitPat _], None) -> true
      | _ -> false
    in
    let r9_named_call name stmt =
      match r9_unpure stmt with
      | Ast.ExprStmt (Ast.CallExpr (_, found, _, _, _, Ast.Static)) -> found = name
      | _ -> false
    in
    let r9_array_u64_join = function
      | Ast.ExprStmt (Ast.CallExpr (_, "array_join",
          [Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3))],
          [], [Ast.LitPat _], Ast.Static)) -> true
      | _ -> false
    in
    let r9_current_owners_call = function
      | Ast.ExprStmt (Ast.CallExpr (_, "r9_current_u64_owners", [], [],
          [Ast.LitPat _; Ast.LitPat _], Ast.Static)) -> true
      | _ -> false
    in
    let r9_safe_command = function
      | Ast.Assert _ -> true
      | stmt when r9_array_u64_open stmt -> true
      | stmt when r9_array_u64_close (r9_unpure stmt) -> true
      | Ast.MergeFractionsStmt _ -> true
      | stmt when r9_named_call "end_ref_readonly" stmt -> true
      | stmt when r9_array_u64_join (r9_unpure stmt) -> true
      | stmt when r9_current_owners_call (r9_unpure stmt) -> true
      | _ -> false
    in
    let r9_return_markers = List.filter_map (function
      | Ast.PureStmt (loc, Ast.BlockStmt (_, [], head :: commands, close, _))
        when r9_return_marker_stmt head -> Some (loc, close, List.map r9_unpure commands)
      | _ -> None) ghost_stmts in
    let r9_guard_return =
      match r9_return_markers with
      | [] -> None
      | [(marker_loc, marker_end, commands)] ->
          if Sys.getenv_opt "SMALLSORT_R9_GUARD_RETURN_RECOVERY" <> Some "1" then
            Ast.static_error marker_loc
              "R9 guard-return marker requires the explicit R9 recovery profile environment" None;
          if commands = [] || not (List.for_all r9_safe_command commands) then
            Ast.static_error marker_loc
              "R9 guard-return marker contains a command outside the checked recovery whitelist" None;
          let binding = match body_tr_defs_ctx.generated_glue with
            | Some binding -> binding
            | None -> Ast.static_error marker_loc
                "R9 guard-return marker has no bound generated selected-Drop glue" None in
          let blocks = basic_blocks_get_list body_cpn in
          let block_ids = List.map (fun block ->
            translate_basic_block_id (BasicBlockRd.id_get block)) blocks in
          let bound_returning_edges = List.filter_map (fun block ->
              let source = translate_basic_block_id (BasicBlockRd.id_get block) in
              match TerminatorKindRd.get
                (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
              | TerminatorKindRd.Drop data
                when TerminatorKindRd.DropData.generated_body_key_get data = binding.glue_key &&
                     TrName.translate_def_path
                       (TerminatorKindRd.DropData.selected_drop_path_get data) = binding.glue_selected_path &&
                     TerminatorKindRd.DropData.selected_drop_hash_get data = binding.glue_selected_hash &&
                     TrName.translate_def_path
                       (TerminatorKindRd.DropData.selected_guard_path_get data) = binding.glue_guard &&
                     List.mem (binding.glue_selected_path, binding.glue_selected_hash, binding.glue_guard)
                       body_tr_defs_ctx.selected_drops &&
                     TerminatorKindRd.DropData.is_bare_local_get data &&
                     not (TerminatorKindRd.DropData.is_replace_get data) ->
                  let target = translate_basic_block_id
                    (TerminatorKindRd.DropData.target_get data) in
                  if not (List.mem target block_ids) then
                    Ast.static_error marker_loc
                      "R9 selected Drop normal target is absent from the original MIR" None;
                  Some (source, target, BasicBlockRd.is_cleanup_get block,
                    LocalDeclIdRd.name_get
                      (PlaceRd.local_get (TerminatorKindRd.DropData.place_get data)))
              | _ -> None) blocks in
          if bound_returning_edges = [] then
            Ast.static_error marker_loc
              "R9 guard-return marker requires a bound bare-local selected Drop edge" None;
          let r9_guard_locals = List.sort_uniq String.compare
            (List.map (fun (_, _, _, local) -> local) bound_returning_edges) in
          if List.length r9_guard_locals <> 1 then
            Ast.static_error marker_loc
              "R9 guard-return marker maps to more than one selected guard local" None;
          Some { r9_guard_return_loc = marker_loc;
                 r9_guard_return_end_loc = marker_end;
                 r9_guard_return_commands = commands;
                 r9_guard_return_key = binding.glue_key;
                 r9_guard_return_path = binding.glue_selected_path;
                 r9_guard_return_hash = binding.glue_selected_hash;
                 r9_guard_return_guard = binding.glue_guard;
                 r9_guard_return_edges = bound_returning_edges }
      | (marker_loc, _, _) :: _ ->
          Ast.static_error marker_loc "R9 guard-return marker is ambiguous" None
    in
    let scope_markers =
      List.filter_map (fun stmt ->
        match marker_stmt "callback_scope_end" stmt with
        | Some lft -> Some (Ast.stmt_loc stmt, lft)
        | None -> None) ghost_stmts
    in
    let first_scope_markers =
      List.filter_map (fun stmt ->
        match marker_stmt "first_callback_scope_end" stmt with
        | Some lft -> Some (Ast.stmt_loc stmt, lft)
        | None -> None) ghost_stmts
    in
    let first_callback, first_strict_scope_ends =
      match marked "first_callback_close", first_scope_markers,
            marked "first_callback_recover" with
      | [], [], [] -> None, []
      | [close_l, close_end, close_lft, close_commands],
        [(cut_l, cut_lft)],
        [recover_l, recover_end, recover_lft, recover_commands]
        when close_lft = cut_lft && cut_lft = recover_lft ->
          let source_pos l = fst (Ast.lexed_loc l) in
          let body_name = TrName.translate_def_path (def_path_get body_cpn) in
          if not (body_name = "insert_tail" ||
                  String.ends_with ~suffix:"::insert_tail" body_name ||
                  body_name = "insert_tail_first_callback_prefix" ||
                  String.ends_with ~suffix:"::insert_tail_first_callback_prefix" body_name) ||
             not (source_pos close_l < source_pos cut_l &&
                  source_pos cut_l < source_pos recover_l) ||
             (let ((_, close_line, _), _) = Ast.lexed_loc close_l in
              let ((_, cut_line, _), _) = Ast.lexed_loc cut_l in
              let ((_, recover_line, _), _) = Ast.lexed_loc recover_l in
              cut_line <> close_line + 1 || recover_line <> cut_line + 1) then
            Ast.static_error cut_l
              "First callback markers require the source insert_tail first-call site"
              None;
          let var name = function
            | Ast.Var (_, found) -> found = name | _ -> false in
          let pvar name = function
            | Ast.LitPat e -> var name e | _ -> false in
          let u64 = function
            | Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3)) -> true
            | _ -> false in
          let ref_initialized name = function
            | Ast.CallExpr (_, "ref_initialized_", [], [], [p], Ast.Static) ->
                pvar name p
            | _ -> false in
          let lifetime_token = function
            | Ast.CallExpr (_, "lifetime_token", [], [], [p], Ast.Static) ->
                pvar "cmp_k" p
            | _ -> false in
          let token_assert coef = function
            | Ast.Assert (_, Ast.CoefAsn (_, Ast.LitPat
                (Ast.Operation (_, Ast.Div, [Ast.IntLit (_, n, _, _, _);
                                             Ast.IntLit (_, d, _, _, _)])), body)) ->
                Big_int.string_of_big_int n = "1" &&
                Big_int.string_of_big_int d = coef && lifetime_token body
            | Ast.Assert (_, body) when coef = "1" -> lifetime_token body
            | _ -> false in
          let close_ref ref_name frac_name = function
            | Ast.Close (_, None, "ref_initialized_", [tp], [p], [],
                Some coef) ->
                u64 tp && pvar ref_name p && pvar frac_name coef
            | _ -> false in
          let diagnostic_extra_fraction = function
            | Ast.LitPat (Ast.Operation (_, Ast.Add,
                [Ast.Var (_, "tail_ref_frac"); Ast.IntLit (_, n, _, _, _)])) ->
                Big_int.string_of_big_int n = "1"
            | _ -> false in
          let close_frac ref_name frac_name allow_diagnostic = function
            | Ast.ExprStmt (Ast.CallExpr (_, "close_frac_borrow", [], [],
                [coef; Ast.LitPat pred], Ast.Static)) ->
                (pvar frac_name coef ||
                 allow_diagnostic && diagnostic_extra_fraction coef) &&
                ref_initialized ref_name pred
            | _ -> false in
          let merge_token = function
            | Ast.MergeFractionsStmt (_, body) -> lifetime_token body
            | _ -> false in
          let close_shape = function
            | [a; b; c; d; e; f] ->
                close_ref "cmp_tail_ref" "tail_ref_frac" a &&
                close_frac "cmp_tail_ref" "tail_ref_frac" true b &&
                close_ref "cmp_sift_ref" "sift_ref_frac" c &&
                close_frac "cmp_sift_ref" "sift_ref_frac" false d &&
                merge_token e &&
                (token_assert "2" f || token_assert "1" f)
            | _ -> false in
          let call name targs args = function
            | Ast.ExprStmt (Ast.CallExpr (_, found, found_targs, [],
                found_args, Ast.Static)) ->
                found = name && targs found_targs && args found_args
            | _ -> false in
          let no_targs = function [] -> true | _ -> false in
          let only_u64 = function [tp] -> u64 tp | _ -> false in
          let full_borrow name = function
            | Ast.ExprCallExpr (_, Ast.TypePredExpr (_, tp, "full_borrow_content"),
                [t; ptr]) -> u64 tp && pvar "t" t && pvar name ptr
            | _ -> false in
          let end_lifetime = call "end_lifetime" no_targs
            (function [k] -> pvar "cmp_k" k | _ -> false) in
          let borrow_end name = call "borrow_end" no_targs
            (function [k; Ast.LitPat p] ->
              pvar "cmp_k" k && full_borrow name p | _ -> false) in
          let open_full name = call "open_full_borrow_content" only_u64
            (function [t; ptr] -> pvar "t" t && pvar name ptr | _ -> false) in
          let one = function
            | Ast.IntLit (_, n, _, _, _) -> Big_int.string_of_big_int n = "1"
            | _ -> false in
          let expr_call name args = function
            | Ast.CallExpr (_, found, [], [], found_args, Ast.Static) ->
                found = name && args found_args
            | _ -> false in
          let take xs = expr_call "take"
            (function [Ast.LitPat n; Ast.LitPat e] ->
              one n && xs e | _ -> false) in
          let singleton name = expr_call "cons"
            (function [Ast.LitPat value; Ast.LitPat rest] ->
              var name value && var "nil" rest | _ -> false) in
          let sift_seq = singleton "current_sift" in
          let tail_seq = singleton "current_tail" in
          let current_rest = expr_call "append"
            (function [Ast.LitPat left; Ast.LitPat right] ->
              sift_seq left && tail_seq right | _ -> false) in
          let bind_current ptr name = function
            | Ast.Assert (_, Ast.PointsTo
                (_, Ast.Deref (_, Ast.Var (_, pointer)), Ast.RegularPointsTo,
                 Ast.VarPat (_, found))) -> pointer = ptr && found = name
            | _ -> false in
          let own_pred = function
            | Ast.CallExpr (_, "own", [tp], [], [t], Ast.Static) ->
                u64 tp && pvar "t" t
            | _ -> false in
          let close_own name = function
            | Ast.Close (_, None, "own", [tp], [t], [Ast.LitPat e], None) ->
                u64 tp && pvar "t" t && var name e
            | _ -> false in
          let close_foreach seq = function
            | Ast.Close (_, None, "foreach", [], [],
                [Ast.LitPat elems; Ast.LitPat own], None) ->
                seq elems && own_pred own
            | _ -> false in
          let close_array ptr seq = function
            | Ast.Close (_, None, "array", [tp], [],
                [p; Ast.LitPat len; Ast.LitPat elems], None) ->
                u64 tp && pvar ptr p && one len && seq elems
            | _ -> false in
          let begin_plus_one = function
            | Ast.Operation (_, Ast.Add, [Ast.Var (_, "begin"); n]) -> one n
            | _ -> false in
          let array_join ptr = call "array_join" only_u64
            (function [Ast.LitPat p] -> ptr p | _ -> false) in
          let foreach_append left right = call "foreach_append" no_targs
            (function [Ast.LitPat xs; Ast.LitPat ys] ->
              left xs && right ys | _ -> false) in
          let recover_shape = function
            | [a; b; c; d; e; f; g; h; i; j; k; l; m; n; o; p; q; r] ->
                token_assert "1" a && end_lifetime b &&
                borrow_end "tail" c && open_full "tail" d &&
                bind_current "tail" "current_tail" e &&
                borrow_end "sift" f && open_full "sift" g &&
                bind_current "sift" "current_sift" h &&
                close_own "current_sift" i && close_own "current_tail" j &&
                close_foreach sift_seq k && close_foreach tail_seq l &&
                close_array "sift" sift_seq m && close_array "tail" tail_seq n &&
                array_join begin_plus_one o && array_join (var "begin") p &&
                foreach_append sift_seq tail_seq q &&
                foreach_append (take (var "xs")) current_rest r
            | _ -> false in
          if not (close_shape close_commands && recover_shape recover_commands) then
            Ast.static_error cut_l
              "Unsupported first callback loan and owner recovery commands"
              None;
          let enclosing =
            List.filter (function
              | Ast.BlockStmt (start,
                  [Ast.TypeWithTypeidDecl (_, name,
                    Ast.CallExpr (_, "typeid_of_lft", [], [], [k], Ast.Static))],
                  [], original_close, _)
                when name = cut_lft && source_pos start < source_pos close_l &&
                     source_pos recover_l < source_pos original_close &&
                     pvar "cmp_k" k -> true
              | _ -> false) ghost_decl_blocks in
          if List.length enclosing <> 1 then
            Ast.static_error cut_l
              "First callback recovery needs exactly one local let_lft binding"
              None;
          let close_stmt = Ast.PureStmt (close_l,
            Ast.BlockStmt (close_l, [], close_commands, close_end, ref [])) in
          let recover_stmt = Ast.PureStmt (recover_l,
            Ast.BlockStmt (recover_l, [], recover_commands, recover_end, ref [])) in
          Some {first_close_loc = close_l; first_scope_end_loc = cut_l;
                first_lft = cut_lft; first_close_stmt = close_stmt;
                first_recover_stmt = recover_stmt}, [(cut_l, cut_lft)]
      | _ ->
          Ast.static_error fn_sig_loc
            "Incomplete or ambiguous first callback recovery markers" None
    in
    let callback_close, callback_recover, strict_lft_scope_ends, callback_scope_start =
      match marked "callback_close", scope_markers, marked "callback_recover" with
      | [], [], [] -> None, None, [], None
      | [close_l, close_end, close_lft, close_commands],
        [(cut_l, cut_lft)],
        [recover_l, recover_end, recover_lft, recover_commands]
        when close_lft = cut_lft && cut_lft = recover_lft ->
          let source_pos l = fst (Ast.lexed_loc l) in
          if not (source_pos close_l < source_pos cut_l &&
                  source_pos cut_l < source_pos recover_l) then
            Ast.static_error cut_l "Callback cleanup markers must be ordered" None;
          (* Admit only the two-source reference protocol. In particular, a
             predicate constructor containing the local lifetime in a term
             must not pass merely because its heap chunk has no type args. *)
          let ty_t = function
            | Ast.IdentTypeExpr (_, None, "T") -> true | _ -> false in
          let ty_lft = function
            | Ast.IdentTypeExpr (_, None, name) -> name = cut_lft | _ -> false in
          let ty_ref = function
            | Ast.RustRefTypeExpr (_, lft, Ast.Shared, elem) ->
                ty_lft lft && ty_t elem
            | _ -> false in
          let var name = function
            | Ast.Var (_, found) -> found = name | _ -> false in
          let pat_var name = function
            | Ast.LitPat e -> var name e | _ -> false in
          let source name = function
            | Ast.CastExpr (_, Ast.PtrTypeExpr (_, tp), e) ->
                ty_t tp && var name e
            | _ -> false in
          let pat_source name = function
            | Ast.LitPat e -> source name e | _ -> false in
          let fbc name = function
            | Ast.ExprCallExpr (_, Ast.TypePredExpr (_, tp, "full_borrow_content"),
                [t; src]) -> ty_t tp && pat_var "t" t && pat_source name src
            | _ -> false in
          let pat_fbc name = function
            | Ast.LitPat e -> fbc name e | _ -> false in
          let ref_pred name = function
            | Ast.CallExpr (_, "ref_initialized_", [], [], [p], Ast.Static) ->
                pat_var name p
            | _ -> false in
          let pat_ref_pred name = function
            | Ast.LitPat e -> ref_pred name e | _ -> false in
          let int_is wanted = function
            | Ast.IntLit (_, value, _, _, _) ->
                Big_int.string_of_big_int value = wanted
            | _ -> false in
          let quarter = function
            | Ast.Operation (_, Ast.Div, [num; den]) ->
                int_is "1" num && int_is "4" den
            | _ -> false in
          let frac name = function
            | Ast.LitPat e -> var name e | _ -> false in
          let bad_right_frac = function
            | Ast.LitPat (Ast.Operation (_, Ast.Add, [lhs; rhs])) ->
                var "right_ref_frac" lhs && int_is "1" rhs
            | _ -> false in
          let call name targs args = function
            | Ast.ExprStmt (Ast.CallExpr (_, found, found_targs, [], found_args, Ast.Static)) ->
                found = name && targs found_targs && args found_args
            | _ -> false in
          let no_targs = function [] -> true | _ -> false in
          let only_t = function [tp] -> ty_t tp | _ -> false in
          let only_lft_t = function [lft; tp] -> ty_lft lft && ty_t tp | _ -> false in
          let close_full name = call "close_full_borrow_content" only_t
            (function [t; src] -> pat_var "t" t && pat_source name src | _ -> false) in
          let borrow name = call "borrow" no_targs
            (function [k; p] -> pat_var "cmp_k" k && pat_fbc name p | _ -> false) in
          let share name = call "share_full_borrow" only_t
            (function [k; t; src] ->
               pat_var "cmp_k" k && pat_var "t" t && pat_source name src
             | _ -> false) in
          let precreate name ref_name = function
            | Ast.DeclStmt (_, [(_, None, found, Some (Ast.CallExpr
                (_, "precreate_ref", [], [], [src], Ast.Static)), _)]) ->
                found = ref_name && pat_source name src
            | _ -> false in
          let init_ref ref_name = call "init_ref_share" only_t
            (function [k; t; p] ->
               pat_var "cmp_k" k && pat_var "t" t && pat_var ref_name p
             | _ -> false) in
          let open_frac ref_name = call "open_frac_borrow" no_targs
            (function [k; p; Ast.LitPat q] ->
               pat_var "cmp_k" k && pat_ref_pred ref_name p && quarter q
             | _ -> false) in
          let open_ref ref_name frac_name = function
            | Ast.Open (_, None, "ref_initialized_", [tp], [p], [],
                Some (Ast.VarPat (_, found))) ->
                ty_t tp && pat_var ref_name p && found = frac_name
            | _ -> false in
          let close_ref ref_name = call "close_ref_own" only_lft_t
            (function [p] -> pat_var ref_name p | _ -> false) in
          let close_tuple = function
            | Ast.Close (_, None, "std_tuple_2__own", [tp1; tp2], [],
                [t; Ast.LitPat (Ast.CastExpr (_,
                  Ast.StructTypeExpr (_, Some "std_tuple_2_", None, [], [vp1; vp2]),
                  Ast.InitializerList (_, [(Some (_, "0"), r0); (Some (_, "1"), r1)])))], None) ->
                ty_ref tp1 && ty_ref tp2 && ty_ref vp1 && ty_ref vp2 &&
                pat_var "t" t && var "right_ref" r0 && var "left_ref" r1
            | _ -> false in
          let close_initialized ref_name frac_name = function
            | Ast.Close (_, None, "ref_initialized_", [tp], [p], [],
                Some coef) ->
                ty_t tp && pat_var ref_name p && frac frac_name coef
            | _ -> false in
          let close_frac ref_name frac_name allow_bad =
            call "close_frac_borrow" no_targs
              (function [coef; p] ->
                 (frac frac_name coef || allow_bad && bad_right_frac coef) &&
                 pat_ref_pred ref_name p
               | _ -> false) in
          let close_shape = function
            | [c0; f0; c1; f1] ->
                close_initialized "left_ref" "left_ref_frac" c0 &&
                close_frac "left_ref" "left_ref_frac" false f0 &&
                close_initialized "right_ref" "right_ref_frac" c1 &&
                close_frac "right_ref" "right_ref_frac" true f1
            | _ -> false in
          let end_lifetime = call "end_lifetime" no_targs
            (function [k] -> pat_var "cmp_k" k | _ -> false) in
          let borrow_end name = call "borrow_end" no_targs
            (function [k; p] -> pat_var "cmp_k" k && pat_fbc name p | _ -> false) in
          let open_full name = call "open_full_borrow_content" only_t
            (function [t; src] -> pat_var "t" t && pat_source name src | _ -> false) in
          let recover_shape = function
            | [e; b0; o0; b1; o1] ->
                end_lifetime e && borrow_end "left_src" b0 &&
                open_full "left_src" o0 && borrow_end "right_src" b1 &&
                open_full "right_src" o1
            | _ -> false in
          if not (close_shape close_commands && recover_shape recover_commands) then
            Ast.static_error cut_l "Unsupported callback loan cleanup command sequence" None;
          let enclosing =
            List.filter (function
              | Ast.BlockStmt (start,
                  [Ast.TypeWithTypeidDecl (_, name,
                    Ast.CallExpr (_, "typeid_of_lft", [], [], [k], Ast.Static))],
                  [], original_close, _)
                when name = cut_lft && source_pos start < source_pos close_l &&
                     source_pos recover_l < source_pos original_close &&
                     pat_var "cmp_k" k -> true
              | _ -> false) ghost_decl_blocks
          in
          let binding_start =
            match enclosing with
            | [Ast.BlockStmt (start, _, _, _, _)] -> start
            | _ -> Ast.static_error cut_l "Callback cleanup needs exactly one local let_lft binding" None
          in
          let in_scope stmt =
            let pos = source_pos (Ast.stmt_loc stmt) in
            source_pos binding_start < pos && pos < source_pos cut_l
          in
          let scoped = ghost_stmts |> List.filter in_scope in
          let pure f = function Ast.PureStmt (_, inner) -> f inner | _ -> false in
          let expected =
            ["left full content", pure (close_full "left_src");
             "left borrow", pure (borrow "left_src");
             "left share", pure (share "left_src");
             "right full content", pure (close_full "right_src");
             "right borrow", pure (borrow "right_src");
             "right share", pure (share "right_src");
             "left precreate", pure (precreate "left_src" "left_ref");
             "left ref share", pure (init_ref "left_ref");
             "right precreate", pure (precreate "right_src" "right_ref");
             "right ref share", pure (init_ref "right_ref");
             "left fraction open", pure (open_frac "left_ref");
             "left ref initialized open", pure (open_ref "left_ref" "left_ref_frac");
             "left ref own", pure (close_ref "left_ref");
             "right fraction open", pure (open_frac "right_ref");
             "right ref initialized open", pure (open_ref "right_ref" "right_ref_frac");
             "right ref own", pure (close_ref "right_ref");
             "tuple own", pure close_tuple;
             "callback close", (fun stmt -> Ast.stmt_loc stmt = close_l)]
          in
          let expected =
            match List.length scoped with
            | 18 -> expected
            | 19 -> expected @ ["escaped ref own control", pure (close_ref "left_ref")]
            | n -> Ast.static_error cut_l
                ("Unexpected callback borrow protocol length: " ^ string_of_int n) None
          in
          List.iter2 (fun (name, check) stmt ->
            if not (check stmt) then
              Ast.static_error (Ast.stmt_loc stmt)
                ("Unexpected callback borrow protocol command: " ^ name) None)
            expected scoped;
          let close_stmt =
            Ast.PureStmt (close_l,
              Ast.BlockStmt (close_l, [], close_commands, close_end, ref [])) in
          let recover_stmt =
            Ast.PureStmt (recover_l,
              Ast.BlockStmt (recover_l, [], recover_commands, recover_end, ref [])) in
          Some (close_l, cut_lft, close_stmt), Some recover_stmt,
          [(cut_l, cut_lft)], Some binding_start
      | _ ->
          let loc = match ghost_stmts with stmt :: _ -> Ast.stmt_loc stmt | [] -> fn_sig_loc in
          Ast.static_error loc "Incomplete or ambiguous callback cleanup markers" None
    in
    let late_begin_markers =
      List.filter_map (fun stmt ->
        match marker_stmt "late_callback_scope_begin" stmt with
        | Some lft -> Some (Ast.stmt_loc stmt, lft)
        | None -> None) ghost_stmts
    in
    let late_scope_end_markers =
      List.filter_map (fun stmt ->
        match marker_stmt "late_callback_scope_end" stmt with
        | Some lft -> Some (Ast.stmt_loc stmt, lft)
        | None -> None) ghost_stmts
    in
    let late_callback =
      match late_begin_markers, marked "late_callback_close",
            late_scope_end_markers, marked "late_callback_recover" with
      | [], [], [], [] -> None
      | [(begin_l, begin_lft)],
        [(close_l, close_end, close_lft, close_commands)],
        [(end_l, end_lft)],
        [(recover_l, recover_end, recover_lft, recover_commands)]
        when begin_lft = close_lft && close_lft = end_lft &&
             end_lft = recover_lft ->
          let source_pos l = fst (Ast.lexed_loc l) in
          let ((begin_file, _begin_line, _), _) = Ast.lexed_loc begin_l in
          let ((close_file, close_line, _), _) = Ast.lexed_loc close_l in
          let ((close_end_file, close_end_line, _), _) =
            Ast.lexed_loc close_end in
          let ((end_file, end_line, _), _) = Ast.lexed_loc end_l in
          let ((recover_file, recover_line, _), _) = Ast.lexed_loc recover_l in
          let body_name = TrName.translate_def_path (def_path_get body_cpn) in
          if not (body_name = "insert_tail" ||
                  String.ends_with ~suffix:"::insert_tail" body_name) ||
             not (source_pos begin_l < source_pos close_l &&
                  source_pos close_l < source_pos end_l &&
                  source_pos end_l < source_pos recover_l) ||
             begin_file <> close_file || close_file <> close_end_file ||
             close_end_file <> end_file || end_file <> recover_file ||
             end_line <> close_end_line + 1 ||
             recover_line <> end_line + 1 then
            Ast.static_error begin_l
              "Late callback markers require one ordered complete insert_tail scope"
              None;
          let begin_precedes_share_close =
            let rec find = function
              | marker :: next :: _ when Ast.stmt_loc marker = begin_l ->
                  (match next with
                   | Ast.PureStmt (_, Ast.ExprStmt
                       (Ast.CallExpr (_, "r6_close_u64_share", [], [],
                         [Ast.LitPat (Ast.Var (_, "r5_late_k"));
                          Ast.LitPat (Ast.Var (_, "t"));
                          Ast.LitPat (Ast.Var (_, "r4_cmp_tmp_ref"))],
                         Ast.Static)))
                   | Ast.ExprStmt
                       (Ast.CallExpr (_, "r6_close_u64_share", [], [],
                         [Ast.LitPat (Ast.Var (_, "r5_late_k"));
                          Ast.LitPat (Ast.Var (_, "t"));
                          Ast.LitPat (Ast.Var (_, "r4_cmp_tmp_ref"))],
                         Ast.Static)) -> true
                   | _ -> false)
              | _ :: rest -> find rest
              | [] -> false in
            find ghost_stmts in
          if not begin_precedes_share_close then
            Ast.static_error begin_l
              "Late callback type scope must begin immediately before reference-own preparation"
              None;
          let var name = function
            | Ast.Var (_, found) -> found = name
            | _ -> false in
          let pvar name = function
            | Ast.LitPat e -> var name e
            | _ -> false in
          let lifetime_token = function
            | Ast.CallExpr (_, "lifetime_token", [], [], [p], Ast.Static) ->
                pvar "r5_late_k" p
            | _ -> false in
          let token_assert coef = function
            | Ast.Assert (_, Ast.CoefAsn (_, Ast.LitPat
                (Ast.Operation (_, Ast.Div, [Ast.IntLit (_, n, _, _, _);
                                             Ast.IntLit (_, d, _, _, _)])), body)) ->
                Big_int.string_of_big_int n = "1" &&
                Big_int.string_of_big_int d = coef && lifetime_token body
            | Ast.Assert (_, body) when coef = "1" -> lifetime_token body
            | _ -> false in
          let merge_token = function
            | Ast.MergeFractionsStmt (_, body) -> lifetime_token body
            | _ -> false in
          if not (match close_commands with
            | [merge; half] -> merge_token merge && token_assert "2" half
            | _ -> false) then
            Ast.static_error close_l
              "Late callback close requires the checked full-to-half token merge"
              None;
          let only_u64 = function
            | [Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3))] -> true
            | _ -> false in
          let full_content ref_name = function
            | Ast.ExprCallExpr (_, Ast.TypePredExpr (_, tp, "full_borrow_content"),
                [t; ptr]) ->
                only_u64 [tp] && pvar "t" t && pvar ref_name ptr
            | Ast.CallExpr (_, "u64_full_borrow_content", [], [], [t; ptr],
                Ast.Static) -> pvar "t" t && pvar ref_name ptr
            | _ -> false in
          let scaled_content share ref_name = function
            | Ast.CallExpr (_, "scaledp", [], [],
                [Ast.LitPat coef; Ast.LitPat content], Ast.Static) ->
                var share coef && full_content ref_name content
            | _ -> false in
          let call name targs args = function
            | Ast.ExprStmt (Ast.CallExpr (_, found, found_targs, [], found_args,
                Ast.Static)) ->
                found = name && targs found_targs && args found_args
            | _ -> false in
          let no_targs = function [] -> true | _ -> false in
          let var_arg name = function [Ast.LitPat e] -> var name e | _ -> false in
          let borrow_end share ref_name = call "borrow_end" no_targs
            (function [k; Ast.LitPat scaled] ->
               pvar "r5_late_k" k && scaled_content share ref_name scaled
             | _ -> false) in
          let open_scaled share ref_name = function
            | Ast.Open (_, None, "scaledp", [],
                [Ast.LitPat coef; Ast.LitPat content], [], None) ->
                var share coef && full_content ref_name content
            | _ -> false in
          let open_full share ref_name = function
            | Ast.Open (_, None, "u64_full_borrow_content", [], [t; ptr], [],
                Some coef) ->
                let found = match coef with
                  | Ast.VarPat (_, found) -> found
                  | Ast.LitPat (Ast.Var (_, found)) -> found
                  | _ -> "" in
                pvar "t" t && pvar ref_name ptr && found = share
            | _ -> false in
          let end_readonly ref_name = call "end_ref_readonly" only_u64
            (var_arg ref_name) in
          let merge_sift = function
            | Ast.MergeFractionsStmt (_, Ast.CallExpr
                (_, "points_to", targs, [],
                 [Ast.LitPat (Ast.Var (_, "sift")); Ast.DummyPat],
                 Ast.Static)) -> only_u64 targs
            | _ -> false in
          let assert_sift = function
            | Ast.Assert (_, Ast.PointsTo
                (_, Ast.Deref (_, Ast.Var (_, "sift")), Ast.RegularPointsTo,
                 Ast.VarPat (_, "r7_sift_current"))) -> true
            | _ -> false in
          let singleton_current = function
            | Ast.CallExpr (_, "cons", [], [],
                [Ast.LitPat value; Ast.LitPat rest], Ast.Static) ->
                var "r7_sift_current" value && var "nil" rest
            | _ -> false in
          let close_sift = function
            | Ast.Close (_, None, "array", [tp], [],
                [Ast.LitPat (Ast.Var (_, "sift"));
                 Ast.LitPat (Ast.IntLit (_, n, _, _, _));
                 Ast.LitPat elems], None) ->
                only_u64 [tp] && Big_int.string_of_big_int n = "1" &&
                singleton_current elems
            | _ -> false in
          let recover_shape = function
            | [token; end_lft;
               tmp_end; tmp_scaled; tmp_full; tmp_readonly;
               sift_end; sift_scaled; sift_full; sift_readonly;
               merge; current; array] ->
                token_assert "1" token &&
                call "end_lifetime" no_targs
                  (function [k] -> pvar "r5_late_k" k | _ -> false) end_lft &&
                borrow_end "r5_tmp_share" "r4_cmp_tmp_ref" tmp_end &&
                open_scaled "r5_tmp_share" "r4_cmp_tmp_ref" tmp_scaled &&
                open_full "r5_tmp_share" "r4_cmp_tmp_ref" tmp_full &&
                end_readonly "r4_cmp_tmp_ref" tmp_readonly &&
                borrow_end "r5_sift_share" "r4_cmp_sift_ref" sift_end &&
                open_scaled "r5_sift_share" "r4_cmp_sift_ref" sift_scaled &&
                open_full "r5_sift_share" "r4_cmp_sift_ref" sift_full &&
                end_readonly "r4_cmp_sift_ref" sift_readonly &&
                merge_sift merge && assert_sift current && close_sift array
            | _ -> false in
          if not (recover_shape recover_commands) then
            Ast.static_error recover_l
              "Late callback recovery does not match the exact scoped loan return"
              None;
          let bindings = List.filter (function
            | Ast.BlockStmt (_, [Ast.TypeWithTypeidDecl (_, name,
                Ast.CallExpr (_, "typeid_of_lft", [], [], [k], Ast.Static))],
                [], _, _) when name = begin_lft && pvar "r5_late_k" k -> true
            | _ -> false) ghost_decl_blocks in
          let original_decl_loc =
            match bindings with
            | [Ast.BlockStmt (start, _, _, _, _)] -> start
            | _ -> Ast.static_error begin_l
               "Late callback scope requires one let_lft 'late = r5_late_k binding"
               None in
          let outer_decl name init = function
            | Ast.DeclStmt (l, [(_, None, found, Some expr, _)])
            | Ast.PureStmt (l, Ast.DeclStmt (_, [(_, None, found, Some expr, _)]))
              when found = name && init expr -> Some l
            | _ -> None in
          let has_begin_lifetime = function
            | Ast.CallExpr (_, "begin_lifetime", [], [], [], Ast.Static) -> true
            | _ -> false in
          let is_false = function Ast.False _ -> true | _ -> false in
          let declarations_before_begin =
            List.filter_map (outer_decl "r5_late_k" has_begin_lifetime) ghost_stmts
            |> List.exists (fun l -> source_pos l < source_pos begin_l) in
          let flag_before_begin =
            List.filter_map (outer_decl "r7_late_unwind" is_false) ghost_stmts
            |> List.exists (fun l -> source_pos l < source_pos begin_l) in
          if not declarations_before_begin || not flag_before_begin then
            Ast.static_error begin_l
              "Late callback scope requires a preceding fresh lifetime and outer unwind flag"
              None;
          let close_stmt = Ast.PureStmt (close_l,
            Ast.BlockStmt (close_l, [], close_commands, close_end, ref [])) in
          let recover_stmt = Ast.PureStmt (recover_l,
            Ast.BlockStmt (recover_l, [], recover_commands, recover_end, ref [])) in
          Some {late_original_decl_loc = original_decl_loc;
                late_begin_loc = begin_l; late_close_loc = close_l;
                late_scope_end_loc = end_l; late_recover_loc = recover_l;
                late_lft = begin_lft;
                late_close_stmt = close_stmt; late_recover_stmt = recover_stmt}
      | _ ->
          let loc = match ghost_stmts with stmt :: _ -> Ast.stmt_loc stmt | [] -> fn_sig_loc in
          Ast.static_error loc "Incomplete or ambiguous late callback markers" None
    in
    if first_callback <> None && callback_close <> None then
      Ast.static_error fn_sig_loc "Overlapping callback recovery protocols" None;
    if late_callback <> None && (first_callback = None || callback_close <> None) then
      Ast.static_error fn_sig_loc
        "Late callback recovery requires the existing first callback protocol alone"
        None;
    let r9_bound_drop_present = match body_tr_defs_ctx.generated_glue with
      | None -> false
      | Some binding -> List.exists (fun block ->
          match TerminatorKindRd.get
            (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
          | TerminatorKindRd.Drop data ->
              TerminatorKindRd.DropData.generated_body_key_get data = binding.glue_key &&
              TrName.translate_def_path
                (TerminatorKindRd.DropData.selected_drop_path_get data) = binding.glue_selected_path &&
              TerminatorKindRd.DropData.selected_drop_hash_get data = binding.glue_selected_hash &&
              TrName.translate_def_path
                (TerminatorKindRd.DropData.selected_guard_path_get data) = binding.glue_guard &&
              List.mem (binding.glue_selected_path, binding.glue_selected_hash, binding.glue_guard)
                body_tr_defs_ctx.selected_drops &&
              TerminatorKindRd.DropData.is_bare_local_get data &&
              not (TerminatorKindRd.DropData.is_replace_get data)
          | _ -> false) (basic_blocks_get_list body_cpn) in
    if Sys.getenv_opt "SMALLSORT_R9_GUARD_RETURN_RECOVERY" = Some "1" &&
       first_callback <> None && late_callback <> None && r9_bound_drop_present &&
       r9_guard_return = None then
      Ast.static_error fn_sig_loc
        "R9 guard-return recovery target body is missing its checked source marker" None;
    (match r9_guard_return with
     | Some _ when first_callback = None || late_callback = None ->
         Ast.static_error fn_sig_loc
           "R9 guard-return marker requires the admitted first and late callback plans" None
     | _ -> ());
    let r19_marker = function
      | Ast.PureStmt (_, Ast.ExprStmt (Ast.CallExpr (_, "r19_insert_tail_unwind_cleanup", [], [], [], Ast.Static)))
      | Ast.ExprStmt (Ast.CallExpr (_, "r19_insert_tail_unwind_cleanup", [], [], [], Ast.Static)) -> true
      | _ -> false
    in
    let r19_unwind_cleanup =
      let unpure = function Ast.PureStmt (_, stmt) -> stmt | stmt -> stmt in
      let var name = function
        | Ast.LitPat (Ast.Var (_, found)) -> found = name
        | _ -> false in
      let marked, stray = List.partition (function
        | Ast.PureStmt (_, Ast.BlockStmt (_, [], head :: _, _, _)) -> r19_marker head
        | _ -> false)
        (List.filter (fun stmt ->
           r19_marker stmt ||
           (match stmt with
            | Ast.PureStmt (_, Ast.BlockStmt (_, _, head :: _, _, _)) -> r19_marker head
            | _ -> false)) ghost_stmts) in
      match marked, stray with
      | [], [] -> None
      | [Ast.PureStmt (l, Ast.BlockStmt (block_l, [], _ :: commands, close, _))], [] ->
          let body_name = TrName.translate_def_path (def_path_get body_cpn) in
          if not (body_name = "b2_three_from_local" ||
                  String.ends_with ~suffix:"::b2_three_from_local" body_name) ||
             first_callback <> None || late_callback <> None ||
             callback_close <> None || r9_guard_return <> None then
            Ast.static_error l
              "R19 cleanup marker outside b2_three_from_local"
              None;
          (match List.map unpure commands with
           | [Ast.Assert (_, Ast.CallExpr (_, "array",
                [Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.FixedWidthRank 3))],
                [], [p; _; Ast.VarPat (_, current)], _));
              Ast.ExprStmt (Ast.CallExpr (_, "r9_drop_u64_owners", [], [],
                [t; current_arg], Ast.Static));
              Ast.ExprStmt (Ast.CallExpr (_, "array_to_array_", [], [],
                [p_arg], Ast.Static))]
             when var "begin" p && var "t" t && var current current_arg &&
                  var "begin" p_arg -> ()
           | _ ->
               Ast.static_error l
                 "R19 cleanup block shape mismatch"
                 None);
          Some (l, Ast.PureStmt (l,
            Ast.BlockStmt (block_l, [], commands, close, ref [])))
      | _ ->
          let loc = match marked @ stray with stmt :: _ -> Ast.stmt_loc stmt | [] -> fn_sig_loc in
          Ast.static_error loc "Ambiguous R19 cleanup marker" None
    in
    let ghost_stmts =
      match r19_unwind_cleanup with
      | None -> ghost_stmts
      | Some (l, stmt) ->
          List.map (fun g ->
            if Ast.stmt_loc g = l then fresh_first_callback_stmt stmt else g) ghost_stmts
    in
    let ghost_stmts =
      match r23_source_array_adapter with
      | None -> ghost_stmts
      | Some plan ->
          let found_pre = ref 0 and found_post = ref 0 in
          let stripped = List.map (fun stmt ->
            if Ast.stmt_loc stmt = plan.r23_pre_marker_loc then (
              incr found_pre;
              plan.r23_pre_stmt)
            else if Ast.stmt_loc stmt = plan.r23_post_marker_loc then (
              incr found_post;
              Ast.NoopStmt plan.r23_post_marker_loc)
            else stmt) ghost_stmts in
          if !found_pre <> 1 || !found_post <> 1 then
            Ast.static_error plan.r23_pre_marker_loc
              "R23 marker blocks did not map to unique translated source annotations"
              None;
          stripped
    in
    let late_strict_scope_ends =
      match late_callback with
      | Some plan -> [(plan.late_scope_end_loc, plan.late_lft)]
      | None -> [] in
    let strict_lft_scope_ends =
      strict_lft_scope_ends @ first_strict_scope_ends @ late_strict_scope_ends @
      (match r23_source_array_adapter with
       | Some plan -> [(plan.r23_post_marker_loc, "'r23_borrow")]
       | None -> []) in
    let source_pos l = fst (Ast.lexed_loc l) in
    let ghost_decl_blocks =
      match late_callback with
      | None -> ghost_decl_blocks
      | Some plan ->
          let found = ref 0 in
          let blocks = List.map (function
            | Ast.BlockStmt (start, decls, [], close, _)
              when List.exists (function
                | Ast.TypeWithTypeidDecl (_, name,
                    Ast.CallExpr (_, "typeid_of_lft", [], [], [Ast.LitPat (Ast.Var (_, "r5_late_k"))], Ast.Static))
                  -> name = plan.late_lft
                | _ -> false) decls ->
                  if source_pos start >= source_pos plan.late_begin_loc ||
                     source_pos plan.late_begin_loc >= source_pos close then
                    Ast.static_error plan.late_begin_loc
                      "Late callback let_lft binding is outside its source loop scope"
                      None;
                  incr found;
                  Ast.BlockStmt (plan.late_begin_loc, decls, [], close, ref [])
            | block -> block) ghost_decl_blocks in
          if !found <> 1 then
            Ast.static_error fn_sig_loc
              "Late callback recovery could not relocate exactly one let_lft declaration"
              None;
          blocks
    in
    let ghost_decl_blocks =
      match r23_source_array_adapter with
      | None -> ghost_decl_blocks
      | Some plan ->
          let found = ref 0 in
          let blocks = List.map (function
            | Ast.BlockStmt (_, decls, [], close, _)
              when List.exists (function
                | Ast.TypeWithTypeidDecl (_, name,
                    Ast.CallExpr (_, "typeid_of_lft", [], [],
                      [Ast.LitPat (Ast.Var (_, token))], Ast.Static))
                  -> name = "'r23_borrow" && token = plan.r23_lifetime_token
                | _ -> false) decls ->
                  if source_pos plan.r23_pre_marker_loc >= source_pos plan.r23_post_marker_loc ||
                     source_pos plan.r23_post_marker_loc >= source_pos close then
                    Ast.static_error plan.r23_pre_marker_loc
                      "R23 let_lft binding's enclosing function scope does not reach the post marker"
                      None;
                  incr found;
                  Ast.BlockStmt
                    (plan.r23_pre_marker_loc, decls, [], close, ref [])
            | block -> block) ghost_decl_blocks in
          if !found <> 1 then
            Ast.static_error plan.r23_pre_marker_loc
              "R23 source adapter could not relocate exactly one let_lft declaration"
              None;
          blocks
    in
    let ghost_stmts =
      let mapped = List.filter_map (fun stmt ->
        let l = Ast.stmt_loc stmt in
        if (match r9_guard_return with
            | Some plan -> l = plan.r9_guard_return_loc
            | None -> false) then Some (Ast.NoopStmt l)
        else if (match first_callback with
            | Some plan -> l = plan.first_close_loc ||
                block_marker "first_callback_recover" stmt <> None
            | None -> false) then Some (Ast.NoopStmt l)
        else match late_callback with
        | Some plan when l = plan.late_begin_loc -> None
        | Some plan when l = plan.late_close_loc || l = plan.late_scope_end_loc ||
                         block_marker "late_callback_recover" stmt <> None ->
            Some (Ast.NoopStmt l)
        | _ ->
            (match callback_close, callback_recover with
             | Some (close_l, _, _), Some _ when l = close_l -> Some (Ast.NoopStmt l)
             | Some _, Some recover_stmt ->
                 (match block_marker "callback_recover" stmt with
                  | Some _ -> Some recover_stmt
                  | None -> Some stmt)
             | _ -> Some stmt)) ghost_stmts in
      let mapped = match late_callback with
        | Some plan -> Ast.NoopStmt plan.late_original_decl_loc :: mapped
        | None -> mapped in
      List.filter (fun stmt ->
           not (List.exists (fun (cut_l, _) -> Ast.stmt_loc stmt = cut_l)
                  strict_lft_scope_ends)) mapped
    in
    let ghost_decl_block_start_stmts =
      ghost_decl_blocks
      |> List.map @@ fun (Ast.BlockStmt (l, decls, [], closeBraceLoc, _)) ->
         let closeBraceLoc =
           match List.find_opt (fun (cut_l, name) ->
             List.exists (function
               | Ast.TypeWithTypeidDecl (_, n, _) -> n = name
               | _ -> false) decls &&
             source_pos l < source_pos cut_l && source_pos cut_l < source_pos closeBraceLoc)
             strict_lft_scope_ends with
           | Some (cut_l, _) -> cut_l
           | None -> closeBraceLoc
         in
         Ast.BlockStmt
           ( l,
             decls,
             [
               ExprStmt
                 (CallExpr (l, "#ghost_decl_block_start", [], [], [], Static));
             ],
             closeBraceLoc,
             ref [] )
    in
    let ghost_decl_block_end_stmts =
      ghost_decl_blocks
      |> Util.flatmap @@ fun (Ast.BlockStmt (l, decls, [], closeBraceLoc, _)) ->
         let end_stmt at =
           Ast.ExprStmt (CallExpr (at, "#ghost_decl_block_end", [], [], [], Static)) in
         match List.find_opt (fun (cut_l, name) ->
           List.exists (function
             | Ast.TypeWithTypeidDecl (_, n, _) -> n = name
             | _ -> false) decls &&
           source_pos l < source_pos cut_l && source_pos cut_l < source_pos closeBraceLoc)
           strict_lft_scope_ends with
         | Some (cut_l, _) when
             List.mem_assoc cut_l first_strict_scope_ends ||
             List.mem_assoc cut_l late_strict_scope_ends ->
             [Ast.NoopStmt cut_l; Ast.NoopStmt closeBraceLoc]
         | Some (cut_l, _) -> [end_stmt cut_l; Ast.NoopStmt closeBraceLoc]
         | None -> [end_stmt closeBraceLoc]
    in
    let* loop_spec_blocks =
      ListAux.try_map translate_loop_spec_block
        (loop_spec_blocks_get_list body_cpn)
    in
    (match late_callback with
     | None -> ()
     | Some plan ->
         let source_line loc =
           let ((_, line, _), _) = Ast.lexed_loc loc in line in
         let candidate_stmts =
           ghost_decl_block_start_stmts @ ghost_decl_block_end_stmts @
           loop_spec_blocks @ ghost_stmts in
         let candidate_count loc =
           List.length (List.filter (fun stmt ->
             source_line (Ast.stmt_loc stmt) = source_line loc) candidate_stmts) in
         List.iter (fun (label, loc) ->
           if candidate_count loc <> 1 then
             Ast.static_error loc
               (Printf.sprintf
                 "Late callback source placeholder %s at line %d has %d translated candidates"
                 label (source_line loc) (candidate_count loc))
               None)
           ["original let_lft start", plan.late_original_decl_loc;
            "explicit binding start", plan.late_begin_loc;
            "late close marker", plan.late_close_loc;
            "strict binding end", plan.late_scope_end_loc;
            "recovery marker", plan.late_recover_loc];
         let binding_starts = List.filter (function
           | Ast.BlockStmt (start, decls,
               [Ast.ExprStmt (Ast.CallExpr (_, "#ghost_decl_block_start", [], [], [], Ast.Static))],
               close, _) ->
               source_line start = source_line plan.late_begin_loc &&
               source_line close = source_line plan.late_scope_end_loc &&
               List.exists (function
                 | Ast.TypeWithTypeidDecl (_, name, _) -> name = plan.late_lft
                 | _ -> false) decls
           | _ -> false) ghost_decl_block_start_stmts in
         if List.length binding_starts <> 1 then
           Ast.static_error plan.late_begin_loc
             "Late callback binding does not start exactly once at its explicit source marker"
             None);
    let stack_addr_occurrences =
      stack_addr_occurrences
      + List.fold_left
          (fun total block ->
            total
            + stack_addr_count
                (AnnotationRd.raw_get (BodyRd.LoopSpecBlock.start_get block)))
          0 (loop_spec_blocks_get_list body_cpn)
    in
    let ghost_stmts =
      ghost_decl_block_start_stmts @ ghost_decl_block_end_stmts @ loop_spec_blocks @ ghost_stmts
    in
    let imp_span_cpn = imp_span_get body_cpn in
    let* imp_loc = translate_span_data imp_span_cpn in
    let open TrBody (struct
      let var_id_trs_map_ref = var_id_trs_map_ref
      let ghost_stmts = ghost_stmts
      let body_imp_loc = imp_loc
      let body_name = TrName.translate_def_path (def_path_get body_cpn)
      let body_def_hash = def_path_hash_get body_cpn
      let body_mir_fingerprint = captured_mir_hash_get body_cpn
      let body_mir_phase = captured_mir_phase_get body_cpn
      let body_tr_defs_ctx = body_tr_defs_ctx
      let is_generated_glue = is_generated_glue
      let strict_lft_scope_ends = strict_lft_scope_ends
      let callback_close = callback_close
      let callback_recover = callback_recover
      let callback_scope_start = callback_scope_start
      let first_callback = first_callback
      let late_callback = late_callback
      let r23_source_array_adapter = r23_source_array_adapter
      let r9_guard_return = r9_guard_return
      let r19_unwind_cleanup = r19_unwind_cleanup
    end) in
    let vdis_cpn = var_debug_info_get_list body_cpn in
    (* Since var id translation map is empty var debug info contains the plain Mir ids *)
    let* vdis =
      Rocq_writer.rocq_suppress_output Args.rocq_writer @@ fun () ->
      ListAux.try_map translate_var_debug_info vdis_cpn
    in
    let env_map, trs_map = make_var_id_name_maps imp_loc vdis in
    let _ = var_id_trs_map_ref :=
      if is_generated_glue then
        { id = TrName.tag_internal "_1"; internal_name = "self" } :: trs_map
      else trs_map in
    let def_kind_cpn = def_kind_get body_cpn in
    let def_kind = DefKind.get def_kind_cpn in
    match def_kind with
    | DefKind.Fn when is_generated_glue ->
        let binding = match body_tr_defs_ctx.generated_glue with
          | Some binding -> binding
          | None -> Ast.static_error fn_sig_loc "Unbound generated Drop glue body" None in
        let descriptor = generated_glue_get body_cpn in
        if VfMirRd.GeneratedGlue.body_key_get descriptor <> binding.glue_key ||
           TrName.translate_def_path (def_path_get body_cpn) <> binding.glue_key ||
           vdis <> [] || ghost_stmts <> [] ||
           ghost_decl_blocks_get_list body_cpn <> [] ||
           loop_spec_blocks_get_list body_cpn <> [] ||
           generics_get_list body_cpn <> [] ||
           impl_block_generics_get_list body_cpn <> [] ||
           not (Capnp.Array.is_empty
             (ContractRd.annotations_get (contract_get body_cpn))) ||
           TranslatorArgs.ignore_unwind_paths then
          Ast.static_error fn_sig_loc "Generated Drop glue has unsupported declarations or configuration" None;
        let inputs = inputs_get_list body_cpn |> List.map D.decode_ty in
        let output = D.decode_ty (output_get body_cpn) in
        let local_decls_cpn = local_decls_get_list body_cpn in
        let receiver_type = match inputs with
          | [input] ->
              (match decode_ty input with
               | `Ref (_, true, `Adt (guard, _, [])) ->
                   guard = binding.glue_guard &&
                   input = D.decode_ty (VfMirRd.GeneratedGlue.receiver_type_get descriptor)
               | _ -> false)
          | _ -> false in
        if List.length inputs <> 1 || List.length local_decls_cpn <> 4 ||
           decode_ty output <> `Tuple [] || not receiver_type ||
           List.map (fun local -> LocalDeclIdRd.name_get (LocalDeclRd.id_get local))
             local_decls_cpn <> ["_0"; "_1"; "_2"; "_3"] ||
           (match local_decls_cpn, inputs with
            | [ret; formal; copied; result], [input] ->
                D.decode_ty (LocalDeclRd.ty_get ret) <> output ||
                D.decode_ty (LocalDeclRd.ty_get formal) <> input ||
                D.decode_ty (LocalDeclRd.ty_get copied) <> input ||
                D.decode_ty (LocalDeclRd.ty_get result) <> output
            | _ -> true) then
          Ast.static_error fn_sig_loc "Generated Drop glue has a mismatched MIR signature" None;
        let* _, selected_contract_opt =
          translate_contract (contract_get binding.glue_method_body) in
        let strong_contract = match selected_contract_opt with
          | Some ((false, (None, Some _), Some (pre, post), false), false) ->
              (match post with
               | "outcome", Ast.SwitchExpr
                   (_, _, [Ast.SwitchExprClause (_, "returning", ["result"], _);
                            Ast.SwitchExprClause (_, "unwinding", [], Ast.False _)], None) ->
                   (false, (None, None), Some (pre, post), false)
               | _ -> Ast.static_error fn_sig_loc
                   "Selected Drop method must have on_unwind_ens false" None)
          | _ -> Ast.static_error fn_sig_loc
              "Selected Drop method lacks the exact checked strong normal/unwind contract" None in
        let name = binding.glue_key in
        Rocq_writer.rocq_print_tuple Args.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_tuple_element Args.rocq_writer begin fun () ->
          Rocq_writer.rocq_print_string_literal Args.rocq_writer name
        end;
        Rocq_writer.rocq_print_tuple_element Args.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_big_record Args.rocq_writer @@ fun () ->
        let split_name = TrName.split_def_path (module_def_path_get body_cpn) name in
        Rocq_writer.rocq_print_big_record_field Args.rocq_writer "inputs" begin fun () ->
          Rocq_writer.rocq_print_small_list Args.rocq_writer @@ fun () ->
          List.iter (fun ty ->
            Rocq_writer.rocq_print_small_list_element Args.rocq_writer @@ fun () ->
            Rocq_writer.rocq_print_data Args.rocq_writer Vf_mir_rocq.rocq_print_ty ty)
            inputs
        end;
        Rocq_writer.rocq_print_big_record_field Args.rocq_writer "output" begin fun () ->
          Rocq_writer.rocq_print_data Args.rocq_writer Vf_mir_rocq.rocq_print_ty output
        end;
        let* local_decls =
          Rocq_writer.rocq_print_big_record_field Args.rocq_writer "local_decls" @@ fun () ->
          Rocq_writer.rocq_print_big_list Args.rocq_writer @@ fun () ->
          ListAux.try_map (fun local ->
            Rocq_writer.rocq_print_big_list_element Args.rocq_writer @@ fun () ->
            translate_local_decl local) local_decls_cpn in
        let ret_place_decl :: param_decl :: other_decls = local_decls in
        let* ret_ty_info = translate_decoded_ty output ret_place_decl.loc in
        let ret_place_decl = { ret_place_decl with ty = lazy ret_ty_info } in
        let* param_ty_info = translate_decoded_ty (List.hd inputs) param_decl.loc in
        (* The generated MIR has the receiver type but no HIR lifetime binder.
           Use the checked method's one late-bound receiver lifetime for the
           private signature; this changes only the erased region spelling. *)
        let* method_gens, _ =
          translate_hir_generics (hir_generics_get binding.glue_method_body) in
        let receiver_lft = match method_gens with
          | [name, Hir.GenParamLifetime]
            when String.length name > 1 && name.[0] = '\'' -> name
          | _ -> Ast.static_error fn_sig_loc
              "Selected Drop method must have one receiver lifetime binder" None in
        (match inputs_get_list binding.glue_method_body with
         | [input] ->
             (match decode_ty (D.decode_ty input) with
              | `Ref (region, true, `Adt (guard, _, []))
                when region = receiver_lft && guard = binding.glue_guard -> ()
              | _ -> Ast.static_error fn_sig_loc
                  "Selected Drop method receiver does not use its checked lifetime" None)
         | _ -> Ast.static_error fn_sig_loc
             "Selected Drop method receiver arity changed" None);
        let glue_tparams = [(receiver_lft, {Ast.sized = false})] in
        let param_ty = match param_ty_info.vf_ty with
          | Ast.RustRefTypeExpr (at, _, Ast.Mutable, guard_ty) ->
              let ty = Ast.RustRefTypeExpr
                (at, Ast.IdentTypeExpr (at, None, receiver_lft),
                 Ast.Mutable, guard_ty) in
              (match param_decl.mutability with
               | Mir.Not -> Ast.ConstTypeExpr (param_decl.loc, ty)
               | Mir.Mut -> ty)
          | _ -> Ast.static_error fn_sig_loc
              "Generated Drop receiver is not a mutable reference" None in
        let* loc = translate_span_data (span_get body_cpn) in
        let* closing_cbrace_loc = LocAux.get_last_col_loc loc in
        let bblocks_cpn = basic_blocks_get_list body_cpn in
        let bare_place place expected =
          LocalDeclIdRd.name_get (PlaceRd.local_get place) = expected &&
          PlaceRd.projection_get_list place = [] in
        let exact_glue_cfg = match bblocks_cpn with
          | [entry; normal] ->
              Stdint.Uint32.to_string
                (BasicBlockIdRd.index_get (BasicBlockRd.id_get entry)) = "0" &&
              Stdint.Uint32.to_string
                (BasicBlockIdRd.index_get (BasicBlockRd.id_get normal)) = "1" &&
              not (BasicBlockRd.is_cleanup_get entry) &&
              not (BasicBlockRd.is_cleanup_get normal) &&
              (match BasicBlockRd.statements_get_list entry with
               | [stmt] ->
                   (match StatementKindRd.get (StatementRd.kind_get stmt) with
                    | StatementKindRd.Assign data ->
                        bare_place (StatementKindRd.AssignData.lhs_place_get data) "_2" &&
                        (match RvalueRd.get
                          (StatementKindRd.AssignData.rhs_rvalue_get data) with
                         | RvalueRd.Use operand ->
                             (match OperandRd.get operand with
                              | OperandRd.Copy place -> bare_place place "_1"
                              | _ -> false)
                         | _ -> false)
                    | _ -> false)
               | _ -> false) &&
              (match TerminatorKindRd.get
                (TerminatorRd.kind_get (BasicBlockRd.terminator_get entry)) with
               | TerminatorKindRd.Call call ->
                   bare_place (FnCallDataRd.destination_get call) "_3" &&
                   (match FnCallDataRd.args_get_list call with
                    | [arg] -> (match OperandRd.get arg with
                        | OperandRd.Move place -> bare_place place "_2"
                        | _ -> false)
                    | _ -> false) &&
                   (match OptionRd.get (FnCallDataRd.target_get call) with
                    | OptionRd.Something ptr ->
                        Stdint.Uint32.to_string
                          (BasicBlockIdRd.index_get (VfMirRd.of_pointer ptr)) = "1"
                    | _ -> false) &&
                   UnwindActionRd.get (FnCallDataRd.unwind_action_get call)
                     = UnwindActionRd.Continue
               | _ -> false) &&
              BasicBlockRd.statements_get_list normal = [] &&
              TerminatorKindRd.get
                (TerminatorRd.kind_get (BasicBlockRd.terminator_get normal))
                = TerminatorKindRd.Return
          | _ -> false in
        if not exact_glue_cfg then
          Ast.static_error loc "Generated Drop glue MIR is not the admitted copy/call/return CFG" None;
        let* bblocks =
          Rocq_writer.rocq_print_big_record_field Args.rocq_writer "basic_blocks" @@ fun () ->
          Rocq_writer.rocq_print_big_list Args.rocq_writer @@ fun () ->
          ListAux.try_filter_map (fun block ->
            translate_basic_block ret_place_decl.id block) bblocks_cpn in
        let vf_bblocks = translate_basic_blocks_to_stmts (find_blocks bblocks) [] in
        let ret_ty = Ast.ConstructedTypeExpr
          (Ast.type_expr_loc ret_ty_info.vf_ty, "fn_outcome", [ret_ty_info.vf_ty]) in
        let body = Ast.Func
          (loc, Ast.Regular, glue_tparams, Some ret_ty, name, [(param_ty, "self")],
           false, (None, None), (let (_, _, pre_post, _) = strong_contract in pre_post),
           false,
           Some (List.map (translate_to_vf_local_decl loc)
                   (ret_place_decl :: other_decls) @ vf_bblocks,
                 closing_cbrace_loc),
           false, []) in
        Ok (None, (split_name, body),
            ({ id = loc; info = env_map } : VF0.debug_info_rust_fe))
    | DefKind.Fn ->
        let def_path = def_path_get body_cpn in
        let name = TrName.translate_def_path def_path in
        Rocq_writer.rocq_print_tuple Args.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_tuple_element Args.rocq_writer begin fun () ->
          Rocq_writer.rocq_print_string_literal Args.rocq_writer name
        end;
        Rocq_writer.rocq_print_tuple_element Args.rocq_writer @@ fun () ->
        Rocq_writer.rocq_print_big_record Args.rocq_writer @@ fun () ->
        let moduleName = module_def_path_get body_cpn in
        (* print_endline ("Translating Mod: " ^ moduleName ^ " --- Body: " ^ name); *)
        let split_name = TrName.split_def_path moduleName name in
        let impl_block_gens = impl_block_generics_get_list body_cpn |> List.map translate_generic_param_def in
        let hir_gens_cpn = hir_generics_get body_cpn in
        let* gens, gens_loc = translate_hir_generics hir_gens_cpn in
        let early_bound_generic_param_names =
          generics_get_list body_cpn
          |> List.map @@ fun generic_param ->
             VfMirRd.GenericParamDef.name_get generic_param
        in
        let early_gens, late_gens =
          List.partition
            (fun (name, kind) ->
              List.mem name early_bound_generic_param_names)
            gens
        in
        let gens = impl_block_gens @ early_gens @ late_gens in
        let vf_tparams = List.map (fun (name, _) -> name) gens in
        let* primed_lft_param_names =
          ListAux.try_filter_map
            (fun (name, kind) ->
              if kind = Hir.GenParamLifetime then Ok (Some name) else Ok None)
            gens
        in
        let lft_param_names =
          List.map TrName.lft_name_without_apostrophe primed_lft_param_names
        in
        let vf_tparams =
          if is_trait_fn_get body_cpn then "Self" :: vf_tparams else vf_tparams
        in
        let clauses =
          impl_block_clauses_get_list body_cpn @ clauses_get_list body_cpn
          |> List.map D.decode_clause
          |> List.map decode_clause
        in
        let hrtb_fnmut_output_bounds =
          clauses
          |> Util.flatmap (function
               | `Projection proj_pred ->
                   let bound_regions = proj_pred.D.bound_regions in
                   let args =
                     List.map decode_generic_arg proj_pred.projection_term.args
                   in
                   let callback_referent = function
                     | `Param name -> Some (HrtbParam name)
                     | `Uint D.U64 -> Some HrtbU64
                     | _ -> None
                   in
                   let matching_fnmut_bounds =
                     clauses
                     |> Util.flatmap (function
                          | `Trait (name, trait_args, trait_bound_regions)
                            when canonicalize_item_name name =
                                 "std::ops::FnMut" &&
                                 trait_args = args &&
                                 trait_bound_regions = bound_regions ->
                              [ () ]
                          | _ -> [])
                   in
                   (match (bound_regions, args, proj_pred.term) with
                   | ( [ r1; r2 ],
                       [ `Type (`Param f);
                         `Type
                           (`Tuple
                             [ `Ref (arg_r1, false, t1);
                               `Ref (arg_r2, false, t2) ]) ],
                       Ty rhs )
                     when r1 <> r2 && r1 = arg_r1 && r2 = arg_r2 &&
                          callback_referent t1 <> None &&
                          callback_referent t1 = callback_referent t2 &&
                          decode_ty rhs = `Bool &&
                          canonicalize_item_name
                            proj_pred.projection_term.def_id
                          = "std::ops::FnOnce::Output" &&
                          matching_fnmut_bounds = [ () ] ->
                       let referent = Option.get (callback_referent t1) in
                       let referent_name = match referent with
                         | HrtbParam name -> name
                         | HrtbU64 -> "u64"
                       in
                       Printf.eprintf
                         "MERGE_HRTB_BOUND function=%s F=%s T=%s regions=%s,%s output=bool\n%!"
                         name f referent_name r1 r2;
                       [ (f, referent) ]
                   | _ -> [])
               | _ -> [])
        in
        State.hrtb_fnmut_output_bounds := hrtb_fnmut_output_bounds;
        let sized_tparams = compute_sized_tparams clauses in
        let vf_tparams_with_bounds = vf_tparams |> List.map (fun x -> (x, {Ast.sized = List.mem x sized_tparams})) in
        let projection_clauses =
          clauses
          |> Util.flatmap (function
               | `Projection proj_clause_cpn when proj_clause_cpn.D.bound_regions = [] -> [ proj_clause_cpn ]
               | _ -> [])
        in
        let* projection_clause_stmts =
          ListAux.try_map
            (translate_projection_clause fn_sig_loc)
            projection_clauses
        in
        let outlives_clauses =
          clauses
          |> Util.flatmap (function
               | `Outlives (r1, r2) -> [ (r1, r2) ]
               | _ -> [])
        in
        let inputs = inputs_get_list body_cpn |> List.map D.decode_ty in
        Rocq_writer.rocq_print_big_record_field Args.rocq_writer "inputs" begin fun () ->
          Rocq_writer.rocq_print_small_list Args.rocq_writer @@ fun () ->
          inputs |> List.iter @@ fun ty ->
            Rocq_writer.rocq_print_small_list_element Args.rocq_writer @@ fun () ->
              Rocq_writer.rocq_print_data Args.rocq_writer Vf_mir_rocq.rocq_print_ty ty
        end;
        let output = D.decode_ty (output_get body_cpn) in
        Rocq_writer.rocq_print_big_record_field Args.rocq_writer "output" begin fun () ->
          Rocq_writer.rocq_print_data Args.rocq_writer Vf_mir_rocq.rocq_print_ty output
        end;
        let implicit_outlives_clauses =
          output :: inputs
          |> Util.flatmap @@ fun ty_cpn ->
             ty_cpn |> decode_ty
             |> extract_implicit_outlives_clauses []
        in
        let outlives_clauses = implicit_outlives_clauses @ outlives_clauses in
        let send_tparams = compute_send_tparams clauses in
        let sync_tparams = compute_sync_tparams clauses in
        let arg_count = List.length inputs in
        let local_decls_cpn = local_decls_get_list body_cpn in
        let* local_decls =
          Rocq_writer.rocq_print_big_record_field Args.rocq_writer "local_decls" @@ fun () ->
            Rocq_writer.rocq_print_big_list Args.rocq_writer @@ fun () ->
              local_decls_cpn |> ListAux.try_map @@ fun local_decl_cpn ->
                Rocq_writer.rocq_print_big_list_element Args.rocq_writer @@ fun () ->
                  translate_local_decl local_decl_cpn
        in
        let all_local_decls = local_decls in
        (* There should always be a return place for each function *)
        let (ret_place_decl :: local_decls) = local_decls in
        let* ret_ty_info =
          translate_decoded_ty output ret_place_decl.loc
        in
        let ret_place_decl = { ret_place_decl with ty = lazy ret_ty_info } in
        let ({
               mutability = ret_mut;
               id = ret_place_id;
               ty = (lazy ret_ty_info);
               loc = ret_place_loc;
             }
              : Mir.local_decl) =
          ret_place_decl
        in
        let ret_ty = ret_ty_info.vf_ty in
        let param_decls, local_decls =
          ListAux.partitioni (fun idx _ -> idx < arg_count) local_decls
        in
        let* param_tys =
          ListAux.try_map
            (fun (ty_cpn, ({ loc } : Mir.local_decl)) ->
              translate_decoded_ty ty_cpn loc)
            (List.combine inputs param_decls)
        in
        let param_decls =
          List.map2
            (fun (decl : Mir.local_decl) ty -> (decl.loc, decl.mutability, decl.id, ty))
            param_decls param_tys
        in
        let vf_param_decls =
          List.map
            (fun (loc, mutability, id, ty_info) ->
              let ty = ty_info.Mir.vf_ty in
              let ty = match mutability with Mir.Not -> Ast.ConstTypeExpr (loc, ty) | Mir.Mut -> ty in
              (ty, id))
            param_decls
        in
        let param_decls = param_decls |> List.map (fun (loc, _, id, ty_info) -> (loc, id, ty_info)) in
        let contract_cpn = contract_get body_cpn in
        let* contract_loc, contract_opt = translate_contract contract_cpn in
        let* is_unsafe = translate_unsafety @@ unsafety_get @@ body_cpn in
        let* contract_template_opt, contract =
          if is_unsafe then
            let* contract =
              Option.to_result
                ~none:
                  (`TrBodyFailed
                    ( contract_loc,
                      "User should provide contract for unsafe functions" ))
                contract_opt
            in
            Ok (None, contract)
          else
            (*safe function*)
            let* pre_post_template =
              if is_drop_fn_get body_cpn then
                let ((_, _, self_ty) :: _) = param_decls in
                let ( PtrTypeExpr
                        ( _,
                          StructTypeExpr (_, Some self_ty, _, _, self_ty_targs)
                        )
                    | RustRefTypeExpr
                        ( _,
                          _,
                          _,
                          StructTypeExpr (_, Some self_ty, _, _, self_ty_targs)
                        ) ) =
                  self_ty.vf_ty
                in
                let (input0 :: _) = inputs_get_list body_cpn in
                let self_gen_args =
                  match decode_ty @@ D.decode_ty input0 with
                  | `Ref (_, _, `Adt (_, _, self_gen_args)) -> self_gen_args
                  | _ -> assert false
                in
                let self_lft_args =
                  Util.flatmap
                    (function
                      | `Lifetime name ->
                          [ TrName.lft_name_without_apostrophe name ]
                      | _ -> [])
                    self_gen_args
                in
                let drop_effect_opt =
                  concrete_drop_effect_decl body_tr_defs_ctx.ghost_decl_map
                    body_tr_defs_ctx.adt_defs self_ty self_ty_targs self_lft_args
                in
                gen_drop_contract body_tr_defs_ctx.adt_defs self_ty
                  self_ty_targs self_lft_args drop_effect_opt fn_sig_loc
              else
                gen_contract body_tr_defs_ctx.adt_defs fn_sig_loc
                  lft_param_names outlives_clauses send_tparams sync_tparams
                  param_decls
                  (ret_place_loc, ret_ty_info)
            in
            let contract_template =
              (false, (None, None), Some pre_post_template, false)
            in
            match contract_opt with
            | None -> Ok (None, (contract_template, false))
            | Some contract -> Ok (Some contract_template, contract)
        in
        let span_cpn = span_get body_cpn in
        let* loc = translate_span_data span_cpn in
        let* closing_cbrace_loc = LocAux.get_last_col_loc loc in
        let mk_fn_decl contract body =
          let ( (nonghost_callers_only : bool),
                ((fn_type_clause : _ option), safetyProof),
                (pre_post : _ option),
                (terminates : bool) ) =
            contract
          in
          Ast.Func
            ( loc,
              Ast.Regular,
              (*type params*) vf_tparams_with_bounds,
              Some
                (if TranslatorArgs.ignore_unwind_paths then ret_ty
                 else
                   Ast.ConstructedTypeExpr
                     (Ast.type_expr_loc ret_ty, "fn_outcome", [ ret_ty ])),
              name,
              vf_param_decls,
              nonghost_callers_only,
              (fn_type_clause, safetyProof),
              (if TranslatorArgs.ignore_unwind_paths then
                 Option.map Rust_parser.result_spec_of_outcome_spec pre_post
               else pre_post),
              terminates,
              body,
              (*virtual*) false,
              (*overrides*) [] )
        in
        let contract, assume_false = contract in
        if assume_false && stack_addr_occurrences <> 0 then
          Ast.static_error fn_sig_loc
            "mir_stack_addr is not admitted in an assumed-false body" None;
        let* body =
          if assume_false then
            Ok
              (mk_fn_decl contract
                 (Some
                    ( [
                        Ast.PureStmt
                          ( loc,
                            ExprStmt
                              (CallExpr
                                 ( loc,
                                   "assume",
                                   [],
                                   [],
                                   [ LitPat (False loc) ],
                                   Static )) );
                      ],
                      closing_cbrace_loc )))
          else
            let rewritten_stack_addrs = ref 0 in
            let resolve_stack_addr use_loc n =
              let raw_id = "_" ^ string_of_int n in
              let matches =
                List.mapi
                  (fun index decl_cpn ->
                    (index, LocalDeclIdRd.name_get
                              (LocalDeclRd.id_get decl_cpn)))
                  local_decls_cpn
                |> List.filter (fun (_, found) -> found = raw_id)
              in
              let fail reason =
                Ast.static_error use_loc
                  (Printf.sprintf "mir_stack_addr(%d): %s" n reason) None
              in
              let index =
                match matches with
                | [(index, _)] when index = n && index > arg_count -> index
                | [(index, _)] when index <= arg_count ->
                    fail "return place and parameters are forbidden"
                | [(index, _)] -> fail "raw MIR local ID does not match its declaration index"
                | [] -> fail "raw MIR local ID is absent"
                | _ -> fail "raw MIR local ID is duplicated"
              in
              let decl = List.nth all_local_decls index in
              let ({ Mir.id = vf_name; ty = (lazy ty_info); loc = decl_loc; _ }
                    : Mir.local_decl) = decl in
              if List.exists
                   (fun ({ id; _ } : var_id_trs_entry) ->
                     id = TrName.tag_internal raw_id)
                   trs_map
              then fail "local has a source/debug name";
              if vf_name <> TrName.tag_internal raw_id then
                fail "translated local name is not the hidden MIR name";
              if List.length
                   (List.filter
                      (fun ({ Mir.id; _ } : Mir.local_decl) -> id = vf_name)
                      all_local_decls)
                 <> 1
              then fail "translated local name is not unique";
              let rec type_description = function
                | Ast.StructTypeExpr (_, Some name, None, [], args) ->
                    name ^ "<" ^ String.concat "," (List.map type_description args) ^ ">"
                | Ast.PtrTypeExpr (_, ty) -> "*" ^ type_description ty
                | Ast.IdentTypeExpr (_, None, name) -> name
                | Ast.ManifestTypeExpr (_, Ast.Int (Ast.Unsigned, Ast.PtrRank)) ->
                    "usize"
                | _ -> fail "struct type contains an unsupported argument shape"
              in
              let type_name =
                match ty_info.vf_ty with
                | Ast.StructTypeExpr (_, Some _, None, [], _) as ty ->
                    type_description ty
                | _ -> fail "local is not a stock materialized struct"
              in
              Printf.eprintf
                "mir_stack_addr certificate: MIR=%s VF=%s type=%s decl=%s use=%s\n%!"
                raw_id vf_name type_name (Ast.string_of_loc decl_loc)
                (Ast.string_of_loc use_loc);
              Ast.AddressOf (use_loc, Ast.Var (use_loc, vf_name))
            in
            let rec rewrite_pat = function
              | Ast.LitPat expr -> Ast.LitPat (rewrite_expr expr)
              | Ast.CtorPat (loc, name, pats) ->
                  Ast.CtorPat (loc, name, List.map rewrite_pat pats)
              | pat -> pat
            and rewrite_expr = function
              | Ast.CallExpr (loc, "mir_stack_addr", [], [],
                    [Ast.LitPat (Ast.IntLit (_, value, true, false,
                       Ast.NoLSuffix))], Ast.Static) ->
                  let spelling = Big_int.string_of_big_int value in
                  let n = int_of_string_opt spelling in
                  let n = match n with
                    | Some n when n > 0 && string_of_int n = spelling -> n
                    | _ -> Ast.static_error loc
                        "mir_stack_addr requires one positive decimal MIR local ID"
                        None
                  in
                  incr rewritten_stack_addrs;
                  resolve_stack_addr loc n
              | Ast.CallExpr (loc, "mir_stack_addr", _, _, _, _) ->
                  Ast.static_error loc
                    "mir_stack_addr requires exactly one unsuffixed decimal literal, no type arguments or indices"
                    None
              | Ast.Operation (loc, op, exprs) ->
                  Ast.Operation (loc, op, List.map rewrite_expr exprs)
              | Ast.CallExpr (loc, name, targs, indices, args, binding) ->
                  Ast.CallExpr (loc, name, targs, List.map rewrite_pat indices,
                    List.map rewrite_pat args, binding)
              | Ast.ExprCallExpr (loc, callee, args) ->
                  Ast.ExprCallExpr
                    (loc, rewrite_expr callee, List.map rewrite_pat args)
              | Ast.PredAsn (loc, name, targs, indices, args, binding) ->
                  Ast.PredAsn (loc, name, targs, List.map rewrite_pat indices,
                    List.map rewrite_pat args, binding)
              | Ast.PredExprAsn (loc, pred, args) ->
                  Ast.PredExprAsn
                    (loc, rewrite_expr pred, List.map rewrite_pat args)
              | Ast.PointsTo (loc, addr, kind, value) ->
                  Ast.PointsTo
                    (loc, rewrite_expr addr, kind, rewrite_pat value)
              | Ast.Sep (loc, left, right) ->
                  Ast.Sep (loc, rewrite_expr left, rewrite_expr right)
              | Ast.IfAsn (loc, cond, left, right) ->
                  Ast.IfAsn
                    (loc, rewrite_expr cond, rewrite_expr left,
                     rewrite_expr right)
              | Ast.CoefAsn (loc, coef, asn) ->
                  Ast.CoefAsn (loc, rewrite_pat coef, rewrite_expr asn)
              | Ast.ExprAsn (loc, expr) ->
                  Ast.ExprAsn (loc, rewrite_expr expr)
              | Ast.ForallAsn (loc, ty, name, expr) ->
                  Ast.ForallAsn (loc, ty, name, rewrite_expr expr)
              | Ast.EnsuresAsn (loc, name, asn) ->
                  Ast.EnsuresAsn (loc, name, rewrite_expr asn)
              | Ast.MatchAsn (loc, expr, pat) ->
                  Ast.MatchAsn
                    (loc, rewrite_expr expr, rewrite_pat pat)
              | Ast.AddressOf (loc, expr) ->
                  Ast.AddressOf (loc, rewrite_expr expr)
              | Ast.Deref (loc, expr) ->
                  Ast.Deref (loc, rewrite_expr expr)
              | Ast.Select (loc, expr, field) ->
                  Ast.Select (loc, rewrite_expr expr, field)
              | Ast.Read (loc, expr, field) ->
                  Ast.Read (loc, rewrite_expr expr, field)
              | Ast.CastExpr (loc, ty, expr) ->
                  Ast.CastExpr (loc, ty, rewrite_expr expr)
              | Ast.ReadArray (loc, array, index) ->
                  Ast.ReadArray
                    (loc, rewrite_expr array, rewrite_expr index)
              | Ast.IfExpr (loc, cond, yes, no) ->
                  Ast.IfExpr
                    (loc, rewrite_expr cond, rewrite_expr yes,
                     rewrite_expr no)
              | Ast.InitializerList (loc, fields) ->
                  Ast.InitializerList
                    (loc, List.map (fun (field, expr) ->
                      (field, rewrite_expr expr)) fields)
              | Ast.Typeid (loc, expr) ->
                  Ast.Typeid (loc, rewrite_expr expr)
              | expr -> expr
            in
            let rec rewrite_stmt = function
              | Ast.PureStmt (loc, stmt) ->
                  Ast.PureStmt (loc, rewrite_stmt stmt)
              | Ast.BlockStmt (loc, decls, stmts, close, addresses) ->
                  Ast.BlockStmt
                    (loc, decls, List.map rewrite_stmt stmts, close, addresses)
              | Ast.InvariantStmt (loc, asn) ->
                  Ast.InvariantStmt (loc, rewrite_expr asn)
              | Ast.Assert (loc, asn) ->
                  Ast.Assert (loc, rewrite_expr asn)
              | Ast.Leak (loc, asn) ->
                  Ast.Leak (loc, rewrite_expr asn)
              | Ast.SpecStmt (loc, pre, post) ->
                  Ast.SpecStmt
                    (loc, rewrite_expr pre, rewrite_expr post)
              | Ast.ExprStmt expr ->
                  Ast.ExprStmt (rewrite_expr expr)
              | Ast.DeclStmt (loc, decls) ->
                  Ast.DeclStmt (loc, List.map
                    (fun (at, ty, name, init, refs) ->
                      (at, ty, name, Option.map rewrite_expr init, refs)) decls)
              | Ast.Open (loc, target, name, targs, indices, args, coef) ->
                  Ast.Open
                    (loc, Option.map rewrite_expr target, name, targs,
                     List.map rewrite_pat indices, List.map rewrite_pat args,
                     Option.map rewrite_pat coef)
              | Ast.Close (loc, target, name, targs, indices, args, coef) ->
                  Ast.Close
                    (loc, Option.map rewrite_expr target, name, targs,
                     List.map rewrite_pat indices, List.map rewrite_pat args,
                     Option.map rewrite_pat coef)
              | Ast.IfStmt (loc, cond, yes, no) ->
                  Ast.IfStmt
                    (loc, rewrite_expr cond, List.map rewrite_stmt yes,
                     List.map rewrite_stmt no)
              | stmt -> stmt
            in
            State.ghost_stmts := List.map rewrite_stmt !State.ghost_stmts;
            if !rewritten_stack_addrs <> stack_addr_occurrences then
              Ast.static_error fn_sig_loc
                "mir_stack_addr appears in an unsupported ghost syntax position"
                None;
            let r23_scoped_local_ids =
              match State.r23_source_array_adapter with
              | None -> []
              | Some plan ->
                  (match plan.r23_ref_local, plan.r23_unsize_local with
                   | Some ref_local, Some cast_local ->
                       [ translate_local_decl_id_ ref_local;
                         translate_local_decl_id_ cast_local ]
                   | _ -> Ast.static_error plan.r23_pre_marker_loc
                       "R23 selected temporary ids were not bound" None)
            in
            let all_body_local_decls = ret_place_decl :: local_decls in
            let r23_scoped_decls =
              match State.r23_source_array_adapter with
              | None -> []
              | Some plan ->
                  let selected = List.filter (fun ({ Mir.id; _ } : Mir.local_decl) ->
                    List.mem id r23_scoped_local_ids) all_body_local_decls in
                  if List.length selected <> 2 then
                    Ast.static_error plan.r23_pre_marker_loc
                      "R23 selected reference temporaries are not unique body locals"
                      None;
                  List.map (fun ({ Mir.mutability = mutability; id;
                                   ty = (lazy ty_info); loc = decl_loc }
                                  : Mir.local_decl) ->
                    let scoped_ty = match ty_info.vf_ty with
                      | Ast.RustRefTypeExpr (at, _, Ast.Mutable, pointee) ->
                          Ast.RustRefTypeExpr
                            (at, Ast.IdentTypeExpr
                               (at, None, "'r23_borrow"), Ast.Mutable, pointee)
                      | _ -> Ast.static_error decl_loc
                          "R23 scoped temporary is not a mutable reference type"
                          None
                    in
                    Ast.DeclStmt
                      (decl_loc,
                       [ (decl_loc,
                          Some (match mutability with
                            | Mir.Mut -> scoped_ty
                            | Mir.Not -> Ast.ConstTypeExpr (decl_loc, scoped_ty)),
                          id, None, (ref false, ref None) ) ])) selected
            in
            (match State.r23_source_array_adapter with
             | Some plan -> plan.r23_scoped_local_decls <- r23_scoped_decls
             | None -> ());
            let vf_local_decls =
              all_body_local_decls
              |> List.filter (fun ({ Mir.id; _ } : Mir.local_decl) ->
                   not (List.mem id r23_scoped_local_ids))
              |> List.map (translate_to_vf_local_decl loc)
            in
            let vf_local_decls =
              match late_callback with
              | None -> vf_local_decls
              | Some _ ->
                  let unwind_flag = "__vf_late_callback_unwind" in
                  if List.exists
                       (fun ({ id; _ } : Mir.local_decl) -> id = unwind_flag)
                       all_local_decls
                  then
                    Ast.static_error fn_sig_loc
                      "Late callback internal unwind flag collides with a source local"
                      None;
                  Ast.DeclStmt
                    (loc,
                     [ (loc, Some (Ast.ManifestTypeExpr (loc, Ast.Bool)),
                       unwind_flag, Some (Ast.False loc), (ref false, ref None)) ])
                    :: vf_local_decls
            in
            let bblocks_cpn = basic_blocks_get_list body_cpn in
            (* R11: place the logical cut after the complete lifetime of the
               compiler-inserted ghost-command result. Keep every native
               Live/Dead and CFG edge, and never manufacture a live binding. *)
            let* r11_cut_plan =
              if Sys.getenv_opt "SMALLSORT_R11_LABEL_STORAGE_PLACEMENT" <> Some "1" ||
                 not (name = "insert_tail" || String.ends_with ~suffix:"::insert_tail" name)
              then Ok None
              else
                let invariants = List.filter_map (function
                  | (Ast.PureStmt (source_at, Ast.InvariantStmt (inv_at, assertion)) as stmt) ->
                      Some (source_at, inv_at, assertion, stmt)
                  | _ -> None) !State.ghost_stmts in
                let fail_at = match invariants with
                  | (_, at, _, _) :: _ -> at | [] -> fn_sig_loc in
                let fail reason = Ast.static_error fail_at
                  ("R11 invariant placement binding refused: " ^ reason) None in
                let require condition reason = if not condition then fail reason in
                let source_at, inv_at, assertion, invariant_stmt = match invariants with
                  | [one] -> one | _ -> fail "missing or ambiguous source invariant" in
                require (State.first_callback <> None && State.late_callback <> None &&
                         State.r9_guard_return <> None && not State.is_generated_glue)
                  "required source-bound callback/guard body is absent";
                let start at = fst (Ast.lexed_loc at) in
                let finish at = snd (Ast.lexed_loc at) in
                let is_ghost data =
                  match D.decode_operand (FnCallDataRd.func_get data) with
                  | Constant {const = Val {ty = {kind = FnDef
                      {id = {name = "VeriFast_ghost_command"}; substs = []}}}} ->
                      FnCallDataRd.args_get_list data = []
                  | _ -> false in
                let* candidates = ListAux.try_map (fun block ->
                  match TerminatorKindRd.get
                      (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
                  | TerminatorKindRd.Call data when is_ghost data ->
                      let* {Mir.span = term_at; _} = translate_source_info
                        (TerminatorRd.source_info_get (BasicBlockRd.terminator_get block)) in
                      let* call_at = translate_span_data (FnCallDataRd.call_span_get data) in
                      Ok (if start call_at = start source_at || start term_at = start source_at
                          then Some (block, data, term_at, call_at) else None)
                  | _ -> Ok None) bblocks_cpn in
                let call_block, data, term_at, call_at =
                  match List.filter_map (fun x -> x) candidates with
                  | [one] -> one | _ -> fail "missing or ambiguous native annotation call" in
                require (term_at = call_at && start call_at = start source_at &&
                         start call_at <= start inv_at && start inv_at < finish call_at)
                  "source/call/terminator span mismatch";
                let destination = FnCallDataRd.destination_get data in
                require (PlaceRd.projection_get_list destination = []) "projected result local";
                let raw_id = LocalDeclIdRd.name_get (PlaceRd.local_get destination) in
                let local = translate_local_decl_id (PlaceRd.local_get destination) in
                let declarations = List.mapi (fun index decl -> index, decl) local_decls_cpn
                  |> List.filter (fun (_, decl) ->
                       LocalDeclIdRd.name_get (LocalDeclRd.id_get decl) = raw_id) in
                let index, declaration = match declarations with
                  | [one] -> one | _ -> fail "missing or ambiguous local declaration" in
                require (raw_id = "_" ^ string_of_int index && index > arg_count &&
                         local = TrName.tag_internal raw_id &&
                         not (List.exists (fun ({id; _} : var_id_trs_entry) ->
                           id = TrName.tag_internal raw_id) trs_map))
                  "ordinary, named or noncanonical result local";
                require (decode_ty (D.decode_ty (LocalDeclRd.ty_get declaration)) = `Tuple [])
                  "annotation result is not the exact unit type";
                let target_id = match OptionRd.get (FnCallDataRd.target_get data) with
                  | OptionRd.Something pointer -> translate_basic_block_id (VfMirRd.of_pointer pointer)
                  | _ -> fail "annotation call has no normal successor" in
                let call_id = translate_basic_block_id (BasicBlockRd.id_get call_block) in
                let target_block = match List.filter (fun block ->
                    translate_basic_block_id (BasicBlockRd.id_get block) = target_id) bblocks_cpn with
                  | [one] when target_id <> call_id -> one
                  | _ -> fail "missing or ambiguous immediate successor" in
                require (not (BasicBlockRd.is_cleanup_get call_block) &&
                         not (BasicBlockRd.is_cleanup_get target_block))
                  "cleanup annotation placement is unsupported";
                let marker action statement = match StatementKindRd.get (StatementRd.kind_get statement) with
                  | StatementKindRd.StorageLive id when action = "Live" ->
                      LocalDeclIdRd.name_get id = raw_id
                  | StatementKindRd.StorageDead id when action = "Dead" ->
                      LocalDeclIdRd.name_get id = raw_id
                  | _ -> false in
                let all_statements = List.concat_map BasicBlockRd.statements_get_list bblocks_cpn in
                require (List.length (List.filter (marker "Live") all_statements) = 1 &&
                         List.length (List.filter (marker "Dead") all_statements) = 1)
                  "missing or ambiguous Live/Dead pair";
                let live = match List.rev (BasicBlockRd.statements_get_list call_block) with
                  | statement :: _ when marker "Live" statement -> statement
                  | _ -> fail "Live is not immediately before the annotation call" in
                let dead = match BasicBlockRd.statements_get_list target_block with
                  | statement :: _ when marker "Dead" statement -> statement
                  | _ -> fail "Dead is not first in the immediate successor" in
                let* {Mir.span = live_at; _} = translate_source_info (StatementRd.source_info_get live) in
                let* {Mir.span = dead_at; _} = translate_source_info (StatementRd.source_info_get dead) in
                require (live_at = call_at && start dead_at = finish call_at)
                  "Live/call/Dead source span mismatch";
                let mentions = ref false in
                Ast.expr_iter (function
                  | Ast.Var (_, name) | Ast.WVar (_, name, _) when name = local -> mentions := true
                  | _ -> ()) assertion;
                require (not !mentions) "invariant refers to the instrumentation local";
                Ok (Some (call_id, target_id, raw_id, local, live_at, dead_at,
                          invariant_stmt, inv_at))
            in
            State.selected_resume_targets := List.filter_map (fun block ->
              match TerminatorKindRd.get (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
              | TerminatorKindRd.Drop data when List.mem
                  (TrName.translate_def_path (TerminatorKindRd.DropData.selected_drop_path_get data),
                   TerminatorKindRd.DropData.selected_drop_hash_get data,
                   TrName.translate_def_path (TerminatorKindRd.DropData.selected_guard_path_get data))
                  body_tr_defs_ctx.selected_drops ->
                  (match UnwindActionRd.get (TerminatorKindRd.DropData.unwind_action_get data) with
                   | UnwindActionRd.Cleanup target ->
                       let id = translate_basic_block_id target in
                       (match List.find_opt (fun block ->
                          translate_basic_block_id (BasicBlockRd.id_get block) = id) bblocks_cpn with
                        | Some resume when BasicBlockRd.is_cleanup_get resume &&
                            BasicBlockRd.statements_get_list resume = [] &&
                            TerminatorKindRd.get (TerminatorRd.kind_get (BasicBlockRd.terminator_get resume)) = TerminatorKindRd.UnwindResume -> Some id
                        | _ -> None)
                   | _ -> None)
              | _ -> None) bblocks_cpn;
            let* bblocks =
              Rocq_writer.rocq_print_big_record_field Args.rocq_writer "basic_blocks" @@ fun () ->
                Rocq_writer.rocq_print_big_list Args.rocq_writer @@ fun () ->
                  ListAux.try_filter_map
                    (fun bblock_cpn ->
                      translate_basic_block ret_place_id bblock_cpn)
                    bblocks_cpn
            in
            let bblocks = match r11_cut_plan with
              | None -> bblocks
              | Some (call_id, target_id, raw_id, local, live_at, dead_at,
                      invariant_stmt, inv_at) ->
                  let fail reason = Ast.static_error inv_at
                    ("R11 invariant placement binding refused: " ^ reason) None in
                  let require condition reason = if not condition then fail reason in
                  let unique id = match List.filter (fun (bb : Mir.basic_block) -> bb.id = id) bblocks with
                    | [one] -> one | _ -> fail "translated block binding is ambiguous" in
                  let call = unique call_id and target = unique target_id in
                  require ((match call.terminator_stmts with [stmt] -> stmt == invariant_stmt | _ -> false) &&
                    call.successors = [target_id] &&
                    (match call.terminator with Mir.GotoTerminator (_, id) -> id = target_id | _ -> false))
                    "translated annotation call/edge differs";
                  require (List.map (fun (bb : Mir.basic_block) -> bb.id)
                    (List.filter (fun (bb : Mir.basic_block) -> List.mem target_id bb.successors) bblocks) = [call_id])
                    "immediate successor has another incoming edge";
                  require (match List.rev call.statements with
                    | Ast.RustStorageLiveStmt (_, at, id, name) :: _ -> at = live_at && id = raw_id && name = local
                    | _ -> false) "translated Live differs";
                  let dead, rest = match target.statements with
                    | (Ast.RustStorageDeadStmt (_, at, id, name) as dead) :: rest
                      when at = dead_at && id = raw_id && name = local -> dead, rest
                    | _ -> fail "translated Dead differs" in
                  (* Refuse any observable use/address-taking, including in
                     ghost assertions. All storage events still execute. *)
                  let used = ref false in
                  let expr e = Ast.expr_iter (function
                    | Ast.Var (_, name) | Ast.WVar (_, name, _) when name = local -> used := true
                    | _ -> ()) e in
                  let rec pat = function
                    | Ast.LitPat e -> expr e
                    | Ast.CtorPat (_, _, pats) -> List.iter pat pats
                    | Ast.WCtorPat (_, _, _, _, _, _, pats, value) ->
                        List.iter pat pats; Option.iter expr value
                    | _ -> () in
                  let inspect = function
                    | Ast.ExprStmt e | Ast.Assert (_, e) | Ast.Leak (_, e)
                    | Ast.InvariantStmt (_, e) | Ast.MergeFractionsStmt (_, e) -> expr e
                    | Ast.SpecStmt (_, pre, post) -> expr pre; expr post
                    | Ast.DeclStmt (_, entries) -> List.iter (fun (_, _, name, init, _) ->
                        require (name <> local) "local is redeclared"; Option.iter expr init) entries
                    | Ast.IfStmt (_, e, _, _) -> expr e
                    | Ast.SwitchStmt (_, e, clauses) ->
                        expr e; List.iter (function
                          | Ast.SwitchStmtClause (_, pattern, _) -> expr pattern
                          | Ast.SwitchStmtDefaultClause _ -> ()) clauses
                    | Ast.ReturnStmt (_, value) -> Option.iter expr value
                    | Ast.Open (_, obj, _, _, indices, args, coef)
                    | Ast.Close (_, obj, _, _, indices, args, coef) ->
                        Option.iter expr obj; List.iter pat (indices @ args); Option.iter pat coef
                    | Ast.SplitFractionStmt (_, _, _, pats, coef) -> List.iter pat pats; Option.iter expr coef
                    | Ast.BlockStmt (_, decls, _, _, _) -> List.iter (function
                        | Ast.TypeWithTypeidDecl (_, _, value) -> expr value
                        | _ -> fail "unsupported nested declaration in placement body") decls
                    | Ast.RustStorageLiveStmt _ | Ast.RustStorageDeadStmt _
                    | Ast.PureStmt _ | Ast.NonpureStmt _ | Ast.NoopStmt _
                    | Ast.GotoStmt _ | Ast.LabelStmt _ | Ast.Break _ | Ast.Continue _ -> ()
                    | _ -> fail "unsupported statement in instrumentation-use check" in
                  List.iter (fun (bb : Mir.basic_block) ->
                    List.iter (Ast.stmt_iter inspect) (bb.statements @ bb.terminator_stmts)) bblocks;
                  require (not !used) "instrumentation result is used or address-taken";
                  Printf.eprintf
                    "R11_INVARIANT_CUT kind=checked_annotation_placement function=%s def_hash=%s mir_fingerprint=%s mir_phase=%s from=%s to=%s mir_local=%s local=%s inv_at=%s live_at=%s dead_at=%s retained_storage=true retained_edges=true\n%!"
                    name (def_path_hash_get body_cpn) (captured_mir_hash_get body_cpn)
                    (captured_mir_phase_get body_cpn) call_id target_id raw_id local
                    (Ast.string_of_loc inv_at) (Ast.string_of_loc live_at) (Ast.string_of_loc dead_at);
                  List.map (fun (bb : Mir.basic_block) ->
                    if bb.id = call_id then {bb with terminator_stmts = []}
                    else if bb.id = target_id then {bb with statements = dead :: invariant_stmt :: rest}
                    else bb) bblocks
            in
            let bblocks =
              match State.first_callback, !State.first_callback_call_loc,
                    !State.first_callback_normal_target with
              | None, None, None -> bblocks
              | Some plan, Some call_loc, Some normal_target
                when !State.first_callback_used ->
                  let source_pos l = fst (Ast.lexed_loc l) in
                  let calls = List.sort
                    (fun (a, _) (b, _) -> compare (source_pos a) (source_pos b))
                    !State.first_fnmut_calls in
                  let prefix =
                    name = "insert_tail_first_callback_prefix" ||
                    String.ends_with
                      ~suffix:"::insert_tail_first_callback_prefix" name in
                  let calls_ok =
                    match calls, prefix with
                    | [(first, `Continue)], true -> first = call_loc
                    | [(first, `Continue); (late, `Cleanup)], false ->
                        first = call_loc && source_pos first < source_pos late &&
                        (let ((first_file, _, _), _) = Ast.lexed_loc first in
                         let ((late_file, _, _), _) = Ast.lexed_loc late in
                         first_file = late_file)
                    | _ -> false in
                  if not calls_ok then
                    Ast.static_error call_loc
                      "First callback recovery requires first Continue and the exact prefix or late Cleanup shape"
                      None;
                  if prefix && List.exists (fun block ->
                       BasicBlockRd.is_cleanup_get block ||
                       (match TerminatorKindRd.get
                         (TerminatorRd.kind_get (BasicBlockRd.terminator_get block)) with
                       | TerminatorKindRd.Drop _ -> true
                       | TerminatorKindRd.Call data ->
                           (match UnwindActionRd.get
                             (FnCallDataRd.unwind_action_get data) with
                            | UnwindActionRd.Cleanup _ -> true
                            | _ -> false)
                       | _ -> false)) bblocks_cpn then
                    Ast.static_error call_loc
                      "First callback prefix contains a Drop or Cleanup edge"
                      None;
                  let matching_call = List.filter (fun (bb : Mir.basic_block) ->
                    match bb.terminator with
                    | Mir.GotoTerminator (at, target) ->
                        at = call_loc && target = normal_target
                    | _ -> false) bblocks in
                  let call_bb = match matching_call with
                    | [bb] -> bb
                    | _ -> Ast.static_error call_loc
                        "First callback normal successor is not unique" None in
                  let original_predecessors = List.filter
                    (fun (bb : Mir.basic_block) ->
                      List.mem normal_target bb.successors) bblocks in
                  if List.map (fun (bb : Mir.basic_block) -> bb.id)
                       original_predecessors <> [call_bb.id] then
                    Ast.static_error call_loc
                      "First callback normal successor has another predecessor"
                      None;
                  let scope_end_id = "#merge_first_callback_scope_end" in
                  let normal_recover_id = "#merge_first_callback_normal_recover" in
                  if List.exists (fun (bb : Mir.basic_block) ->
                       bb.id = scope_end_id || bb.id = normal_recover_id) bblocks ||
                     not (List.exists (fun (bb : Mir.basic_block) ->
                       bb.id = normal_target) bblocks) then
                    Ast.static_error call_loc
                      "First callback local continuation collides with the MIR CFG"
                      None;
                  let reset_bb (bb : Mir.basic_block) =
                    {bb with external_predecessor_count = 0;
                             internal_predecessor_count = 0;
                             walk_state = Mir.NotSeen; is_block_head = false;
                             parent = None; children = []} in
                  let call_bb' =
                    {call_bb with
                      terminator = Mir.GotoTerminator (call_loc, scope_end_id);
                      successors = [scope_end_id]} in
                  let scope_end_bb = reset_bb
                    {call_bb with id = scope_end_id; statements = [];
                      terminator_stmts =
                        [Ast.ExprStmt (Ast.CallExpr
                          (plan.first_scope_end_loc, "#ghost_decl_block_end",
                           [], [], [], Ast.Static))];
                      terminator = Mir.GotoTerminator
                        (plan.first_scope_end_loc, normal_recover_id);
                      successors = [normal_recover_id]} in
                  let normal_recover_bb = reset_bb
                    {call_bb with id = normal_recover_id;
                      statements = [fresh_first_callback_stmt plan.first_recover_stmt];
                      terminator_stmts = [];
                      terminator = Mir.GotoTerminator
                        (plan.first_scope_end_loc, normal_target);
                      successors = [normal_target]} in
                  List.map (fun (bb : Mir.basic_block) ->
                    if bb.id = call_bb.id then call_bb' else bb) bblocks @
                  [scope_end_bb; normal_recover_bb]
              | _ -> Ast.static_error fn_sig_loc
                  "First callback recovery markers did not match a call" None
            in
            let bblocks =
              match State.late_callback, !State.late_callback_call with
              | None, None -> bblocks
              | Some plan, Some (call_loc, normal_target, cleanup_target)
                when !State.late_callback_used &&
                     (match State.first_callback,
                            !State.first_callback_call_loc,
                            !State.first_callback_normal_target with
                      | Some _, Some _, Some _ -> true | _ -> false) ->
                  let source_cleanup = List.find_opt (fun block ->
                    translate_basic_block_id (BasicBlockRd.id_get block) = cleanup_target)
                    bblocks_cpn in
                  (match source_cleanup with
                   | Some block when BasicBlockRd.is_cleanup_get block -> ()
                   | _ -> Ast.static_error call_loc
                       "Late callback Cleanup target is missing or not a cleanup block"
                       None);
                  let has_block id = List.exists
                    (fun (bb : Mir.basic_block) -> bb.id = id) bblocks in
                  if not (has_block normal_target && has_block cleanup_target) then
                    Ast.static_error call_loc
                      "Late callback original normal or Cleanup target is missing" None;
                  let scope_end_id = "#merge_late_callback_scope_end" in
                  let recover_id = "#merge_late_callback_recover" in
                  if List.exists (fun (bb : Mir.basic_block) ->
                       bb.id = scope_end_id || bb.id = recover_id) bblocks then
                    Ast.static_error call_loc
                      "Late callback synthetic continuation collides with the MIR CFG"
                      None;
                  let call_bb = match List.filter (fun (bb : Mir.basic_block) ->
                    match bb.terminator with
                    | Mir.GotoTerminator (at, target) ->
                        at = call_loc && target = scope_end_id
                    | _ -> false) bblocks with
                    | [bb] -> bb
                    | _ -> Ast.static_error call_loc
                        "Late callback call block is not unique" None in
                  let reset_bb (bb : Mir.basic_block) =
                    {bb with external_predecessor_count = 0;
                             internal_predecessor_count = 0;
                             walk_state = Mir.NotSeen; is_block_head = false;
                             parent = None; children = []} in
                  let scope_end_bb = reset_bb
                    {call_bb with id = scope_end_id; statements = [];
                      terminator_stmts =
                        [Ast.ExprStmt (Ast.CallExpr
                          (plan.late_scope_end_loc, "#ghost_decl_block_end",
                           [], [], [], Ast.Static))];
                      terminator = Mir.GotoTerminator
                        (plan.late_scope_end_loc, recover_id);
                      successors = [recover_id]} in
                  let recover_bb = reset_bb
                    {call_bb with id = recover_id;
                      statements = [plan.late_recover_stmt];
                      terminator_stmts =
                        [Ast.IfStmt
                          (call_loc,
                           Ast.Var (call_loc, "__vf_late_callback_unwind"),
                           [Ast.GotoStmt (call_loc, cleanup_target)],
                           [Ast.GotoStmt (call_loc, normal_target)])];
                      terminator = Mir.EncodedTerminator;
                      successors = [cleanup_target; normal_target]} in
                  Printf.eprintf
                    "MERGE_LATE_CALLBACK_RECOVERY function=%s call=%s normal=%s cleanup=%s lifetime=%s\n%!"
                    name (Ast.string_of_loc call_loc) normal_target cleanup_target
                    plan.late_lft;
                  bblocks @ [scope_end_bb; recover_bb]
              | _ -> Ast.static_error fn_sig_loc
                  "Late callback recovery markers did not match the actual Cleanup call"
                  None
            in
            let toplevel_blocks = find_blocks bblocks in
            let vf_bblocks =
              translate_basic_blocks_to_stmts toplevel_blocks []
            in
            let vf_bblocks =
              match State.first_callback, !State.first_callback_call_loc,
                    !State.first_callback_normal_target with
              | None, None, None -> vf_bblocks
              | Some plan, Some call_loc, Some normal_target ->
                  let matches_scope = function
                    | Ast.BlockStmt (_,
                        [Ast.TypeWithTypeidDecl (_, name, _) as _decl],
                        Ast.ExprStmt (Ast.CallExpr
                          (_, "#strict_lft_binding_scope", [Ast.IdentTypeExpr (_, None, lft)],
                           [], [], Ast.Static)) :: _, _, _)
                      when name = plan.first_lft && lft = plan.first_lft -> true
                    | _ -> false in
                  let found = ref 0 in
                  let panic_continuation =
                    [Ast.Assert (call_loc, Ast.False call_loc);
                     Ast.LabelStmt (call_loc, State.first_callback_unwind_label);
                     fresh_first_callback_stmt plan.first_recover_stmt;
                     Ast.ReturnStmt (call_loc, Some (Ast.CallExpr
                       (call_loc, "unwinding", [], [], [], Ast.Static)))] in
                  let rec splice_stmt stmt = match stmt with
                    | Ast.BlockStmt (at, decls, stmts, close, addresses) ->
                        Ast.BlockStmt
                          (at, decls, splice_stmts stmts, close, addresses)
                    | stmt -> stmt
                  and splice_stmts stmts =
                    List.concat_map (fun stmt ->
                      if matches_scope stmt then (
                        incr found;
                        [stmt] @ panic_continuation)
                      else [splice_stmt stmt]) stmts in
                  let result = splice_stmts vf_bblocks in
                  if !found <> 1 then
                    Ast.static_error call_loc
                      "First callback local unwind continuation has no unique strict scope"
                      None;
                  Printf.eprintf
                    "MERGE_FIRST_CALLBACK_LOCAL_CONTINUE function=%s call=%s target=%s lifetime=%s\n%!"
                    name (Ast.string_of_loc call_loc) normal_target
                    plan.first_lft;
                  result
              | _ -> Ast.static_error fn_sig_loc
                  "First callback recovery markers did not match a call" None
            in
            (* This deliberately invalid generated call is a separately
               profiled control. Select its local and receiver from the MIR
               Drop edge, then place it immediately after that local's real
               Rust StorageDead. The generated receiver declaration and the
               ordinary Drop finish remain untouched. *)
            let vf_bblocks =
              match Sys.getenv_opt "SMALLSORT_DROP_RECEIVER_CONTROL",
                    body_tr_defs_ctx.generated_glue with
              | Some "post_retirement_drop", Some binding ->
                  let qualified_drops = List.filter_map (fun block ->
                    match TerminatorKindRd.get
                      (TerminatorRd.kind_get
                        (BasicBlockRd.terminator_get block)) with
                    | TerminatorKindRd.Drop data
                      when not (BasicBlockRd.is_cleanup_get block) &&
                           TerminatorKindRd.DropData.generated_body_key_get data = binding.glue_key &&
                           TrName.translate_def_path
                             (TerminatorKindRd.DropData.selected_drop_path_get data) =
                               binding.glue_selected_path &&
                           TerminatorKindRd.DropData.selected_drop_hash_get data =
                               binding.glue_selected_hash &&
                           TrName.translate_def_path
                             (TerminatorKindRd.DropData.selected_guard_path_get data) =
                               binding.glue_guard &&
                           List.mem
                             (TrName.translate_def_path
                                (TerminatorKindRd.DropData.selected_drop_path_get data),
                              TerminatorKindRd.DropData.selected_drop_hash_get data,
                              TrName.translate_def_path
                                (TerminatorKindRd.DropData.selected_guard_path_get data))
                             body_tr_defs_ctx.selected_drops &&
                           TerminatorKindRd.DropData.is_bare_local_get data &&
                           not (TerminatorKindRd.DropData.is_replace_get data) ->
                        let place = TerminatorKindRd.DropData.place_get data in
                        let mir_local_id =
                          LocalDeclIdRd.name_get (PlaceRd.local_get place) in
                        let target = translate_basic_block_id
                          (TerminatorKindRd.DropData.target_get data) in
                        Some (mir_local_id, "__vf_drop_receiver_" ^ target)
                    | _ -> None) bblocks_cpn in
                  (match qualified_drops with
                   | [] -> vf_bblocks
                   | [(mir_local_id, receiver_name)] ->
                       let injected at =
                         Ast.ExprStmt (Ast.CallExpr
                           (at, binding.glue_key,
                            [Ast.InferredTypeExpr at], [],
                            [Ast.LitPat (Ast.Var (at, receiver_name))], Ast.Static))
                       in
                       let found = ref 0 in
                       let rec insert_stmt stmt =
                         match stmt with
                         | Ast.RustStorageDeadStmt (at, mir_at, id, local)
                           when id = mir_local_id ->
                             incr found;
                             [stmt; injected at]
                         | Ast.BlockStmt (at, decls, stmts, close, addresses) ->
                             [Ast.BlockStmt
                               (at, decls, List.concat_map insert_stmt stmts,
                                close, addresses)]
                         | stmt -> [stmt]
                       in
                       let result = List.concat_map insert_stmt vf_bblocks in
                       if !found <> 1 then
                         Ast.static_error fn_sig_loc
                           "Post-retirement generated Drop control did not find exactly one matching StorageDead"
                           None;
                       result
                   | _ -> Ast.static_error fn_sig_loc
                       "Post-retirement generated Drop control found multiple qualified Drops" None)
              | _ -> vf_bblocks
            in
            (match State.r19_unwind_cleanup with
             | Some (l, _) when not !State.r19_unwind_cleanup_used ->
                 Ast.static_error l
                   "R19 cleanup marker did not follow insert_tail"
                   None
             | _ -> ());
            (match State.r23_source_array_adapter with
             | Some plan when not plan.r23_ref_seen ||
                  not plan.r23_unsize_seen || not plan.r23_call_seen ->
                 Ast.static_error plan.r23_pre_marker_loc
                   "R23 source adapter was not consumed by exactly one Ref-Unsize-as_mut_ptr chain"
                   None
             | Some _ when !State.r23_adapter_post_bridge <> None ->
                 Ast.static_error fn_sig_loc
                   "R23 source adapter left an unconsumed slice-to-array borrow bridge"
                   None
             | Some plan when not plan.r23_scope_decls_inserted ->
                 Ast.static_error plan.r23_pre_marker_loc
                   "R23 scoped Ref/Unsize declarations were not placed inside the strict source interval"
                   None
             | _ -> ());
            (match State.r9_guard_return with
             | None -> ()
             | Some plan ->
                 let used = List.sort compare !State.r9_guard_return_used in
                 let expected = List.sort compare plan.r9_guard_return_edges in
                 if used <> expected then
                   Ast.static_error plan.r9_guard_return_loc
                     "R9 guard-return checked commands were not attached to every exact MIR returning edge"
                     None);
            let vf_bblocks =
              match State.callback_close, State.callback_recover, !State.callback_call_loc with
              | None, None, None -> vf_bblocks
              | Some _, Some recover, Some call_loc
                when !State.callback_used && !State.fnmut_call_count = 1 ->
                  (* Keep the normal return inside its own miniblock.  The
                     unwind Goto still reaches the outer label through the
                     stock BlockStmt label continuation. *)
                  [Ast.BlockStmt
                     (call_loc, [], vf_bblocks, call_loc, ref [])] @
                  [ Ast.Assert (call_loc, Ast.False call_loc);
                    Ast.LabelStmt (call_loc, State.callback_unwind_label);
                    recover;
                    Ast.ReturnStmt
                      (call_loc, Some (Ast.CallExpr
                        (call_loc, "unwinding", [], [], [], Ast.Static))) ]
              | _ -> Ast.static_error fn_sig_loc "Callback cleanup marker did not match a call" None
            in
            let vf_bblocks =
              match State.r23_source_array_adapter with
              | Some plan ->
                  (match plan.r23_unwind_epilogue with
                   | None -> Ast.static_error plan.r23_pre_marker_loc
                       "R23 adapter did not preserve the original method unwind outcome"
                       None
                   | Some epilogue -> vf_bblocks @ epilogue)
              | None -> vf_bblocks
            in
            Ok
              (mk_fn_decl contract
                 (Some
                    ( projection_clause_stmts @ vf_local_decls @ vf_bblocks,
                      closing_cbrace_loc )))
        in
        let body_sig_opt =
          match contract_template_opt with
          | None -> None
          | Some contract_template ->
              let body_sig = mk_fn_decl contract_template None in
              Some (split_name, body_sig)
        in
        r23_source_array3_interp_active := false;
        Ok
          ( body_sig_opt,
            (split_name, body),
            ({ id = loc; info = env_map } : VF0.debug_info_rust_fe) )
    | DefKind.AssocFn -> failwith "Todo: MIR Body kind AssocFn"
    | _ -> Error (`TrBodyFatal "Unknown MIR Body kind")

  let translate_visibility (vis : D.visibility) =
    match vis with
    | Public -> Ok Mir.Public
    | Restricted -> Ok Mir.Restricted

  let translate_field_def ({name={name}; span; ty; vis} : D.variant_def_field_def) =
    let* loc = translate_decoded_span_data span in
    (* Todo @Nima: We are using the whole field definition span as the type span which should be corrected *)
    let* ty_info = translate_decoded_ty ty loc in
    let* vis = translate_visibility vis in
    Ok Mir.{ name; ty = ty_info; vis; loc }

  let translate_to_vf_field_def
      (Mir.{ name; ty = ty_info; vis; loc } : Mir.field_def_tr) =
    Ast.Field
      ( loc,
        Ast.Real (*ghostness*),
        ty_info.vf_ty,
        name,
        Ast.Instance (*method_binding*),
        Ast.Public (*visibility*),
        true (*final*),
        None (*expr option*) )

  let translate_variant_def ({span; name; fields} : D.variant_def) =
    let open VariantDefRd in
    let* loc = translate_decoded_span_data span in
    let* fields = ListAux.try_map translate_field_def fields in
    let open Mir in
    Ok Mir.{ loc; name; fields }

  let gen_adt_full_borrow_content adt_kind name tparams lft_params
      (variants : Mir.variant_def_tr list) adt_def_loc preciseness =
    let open Ast in
    match adt_kind with
    | Mir.Enum | Mir.Union ->
        failwith "Todo: Gen ADT full borrow content for Enum or Union"
    | Mir.Struct ->
        let fbor_content_name = name ^ "_full_borrow_content" in
        let tid_param_name = "tid" in
        let ptr_param_name = "l" in
        let vf_tparams = lft_params @ tparams in
        let fbor_content_params =
          [
            ( IdentTypeExpr (adt_def_loc, None (*package name*), "thread_id_t"),
              tid_param_name );
            ( PtrTypeExpr
                ( adt_def_loc,
                  StructTypeExpr
                    ( adt_def_loc,
                      Some name,
                      None,
                      [],
                      List.map
                        (fun x -> IdentTypeExpr (adt_def_loc, None, x))
                        vf_tparams ) ),
              ptr_param_name );
          ]
        in
        let* fields =
          match variants with
          | [ variant_def ] -> Ok variant_def.fields
          | _ ->
              Error
                (`GenAdtFullBorContent "Struct ADT def should have one variant")
        in
        let field_chunk (f : Mir.field_def_tr) =
          let* fc =
            f.ty.interp.points_to
              (Var (f.loc, tid_param_name))
              (Read (f.loc, Var (f.loc, ptr_param_name), f.name))
              (Some f.name)
          in
          Ok (f.loc, fc)
        in
        let* field_chunks =
          match ListAux.try_map field_chunk fields with
          | Ok field_chunks -> Ok field_chunks
          | Error msg -> Error (`GenAdtFullBorContent msg)
        in
        let own_args =
          [
            LitPat (Var (adt_def_loc, tid_param_name));
            LitPat
              (CastExpr
                 ( adt_def_loc,
                   Ast.StructTypeExpr
                     ( adt_def_loc,
                       Some name,
                       None,
                       [],
                       List.map
                         (fun x -> IdentTypeExpr (adt_def_loc, None, x))
                         vf_tparams ),
                   InitializerList
                     ( adt_def_loc,
                       List.map
                         (fun (f : Mir.field_def_tr) ->
                           (None, Var (f.loc, f.name)))
                         fields ) ));
          ]
        in
        let own_pred =
          CallExpr
            ( adt_def_loc,
              name ^ "_own",
              (*type arguments*)
              List.map
                (fun x -> IdentTypeExpr (adt_def_loc, None, x))
                vf_tparams,
              (*indices*) [],
              (*arguments*)
              own_args,
              if vf_tparams = [] then PredFamCall else PredCtorCall )
        in
        let padding_pred =
          CallExpr
            ( adt_def_loc,
              padding_pred_name name,
              List.map
                (fun x -> IdentTypeExpr (adt_def_loc, None, x))
                vf_tparams,
              [],
              [ LitPat (Var (adt_def_loc, ptr_param_name)) ],
              PredFamCall )
        in
        let (Some body_asn) =
          AstAux.list_to_sep_conj field_chunks
            (Some (Ast.Sep (adt_def_loc, padding_pred, own_pred)))
        in
        let fbor_content_pred_ctor =
          PredCtorDecl
            ( adt_def_loc,
              fbor_content_name,
              vf_tparams (* type parameters*),
              fbor_content_params,
              [],
              (if preciseness then Some 0 else None)
              (* (Some n) means the predicate is precise and the first n parameters are input parameters *),
              body_asn )
        in
        Ok fbor_content_pred_ctor

  let add_type_interp_asns loc tparams asn =
    List.fold_right
      (fun x asn ->
        Ast.Sep
          ( loc,
            CallExpr
              ( loc,
                "type_interp",
                [ IdentTypeExpr (loc, None, x) ],
                [],
                [],
                Static ),
            asn ))
      tparams asn

  let add_send_asns loc send_tparams asn =
    List.fold_right
      (fun x asn -> Ast.Sep (loc, mk_send_tparam_asn loc x, asn))
      send_tparams asn

  let add_sync_asns loc sync_tparams asn =
    List.fold_right
      (fun x asn -> Ast.Sep (loc, mk_sync_asn loc x, asn))
      sync_tparams asn

  let gen_send_proof_oblig adt_def_loc name tparams vf_tparams =
    let open Ast in
    let params = [ (IdentTypeExpr (adt_def_loc, None, "thread_id_t"), "t1") ] in
    let tparams_targs =
      List.map (fun (x, _) -> IdentTypeExpr (adt_def_loc, None, x)) vf_tparams
    in
    let pre =
      Sep
        ( adt_def_loc,
          mk_send_asn adt_def_loc (StructTypeExpr (adt_def_loc, Some name, None, [], tparams_targs)),
          CallExpr
            ( adt_def_loc,
              name ^ "_own",
              tparams_targs,
              [],
              [ VarPat (adt_def_loc, "t0"); VarPat (adt_def_loc, "v") ],
              if vf_tparams = [] then PredFamCall else PredCtorCall ))
    in
    let pre = add_type_interp_asns adt_def_loc tparams pre in
    let post =
      CallExpr
        ( adt_def_loc,
          name ^ "_own",
          tparams_targs,
          [],
          [ LitPat (Var (adt_def_loc, "t1")); LitPat (Var (adt_def_loc, "v")) ],
          if vf_tparams = [] then PredFamCall else PredCtorCall )
    in
    let post = add_type_interp_asns adt_def_loc tparams post in
    Func
      ( adt_def_loc,
        Lemma
          ( false
            (*indicates whether an axiom should be generated for this lemma*),
            None (*trigger*) ),
        vf_tparams (*type parameters*),
        None (*return type*),
        name ^ "_send",
        params,
        false (*nonghost_callers_only*),
        (None, None)
        (*implemented function type, with function type type arguments and function type arguments*),
        Some (pre, ("result", post)) (*contract*),
        false (*terminates*),
        None (*body*),
        false (*virtual*),
        [] (*overrides*) )

  let gen_own_variance_proof_oblig adt_def_loc name lft_params tparams variances
      fds_no_zst =
    let open Ast in
    assert (List.length variances = List.length lft_params + List.length tparams);
    let lft_param_variances, tparam_variances =
      Util.take_drop (List.length lft_params) variances
    in
    let lft_params01, all_lft_params_and_pres =
      List.split
        (List.map2
           (fun x variance ->
             if variance = VarianceRd.Invariant then ((x, x), ([ x ], []))
             else
               let x0 = x ^ "0" in
               let x1 = x ^ "1" in
               ( (x0, x1),
                 ( [ x0; x1 ],
                   match variance with
                   | Covariant ->
                       [
                         ExprAsn
                           ( adt_def_loc,
                             CallExpr
                               ( adt_def_loc,
                                 "lifetime_inclusion",
                                 [],
                                 [],
                                 [
                                   LitPat
                                     (Rust_parser.expr_of_lft_param adt_def_loc
                                        x1);
                                   LitPat
                                     (Rust_parser.expr_of_lft_param adt_def_loc
                                        x0);
                                 ],
                                 Static ) );
                       ]
                   | Contravariant ->
                       [
                         ExprAsn
                           ( adt_def_loc,
                             CallExpr
                               ( adt_def_loc,
                                 "lifetime_inclusion",
                                 [],
                                 [],
                                 [
                                   LitPat
                                     (Rust_parser.expr_of_lft_param adt_def_loc
                                        x0);
                                   LitPat
                                     (Rust_parser.expr_of_lft_param adt_def_loc
                                        x1);
                                 ],
                                 Static ) );
                       ]
                   | _ -> [] ) ))
           lft_params lft_param_variances)
    in
    let all_lft_params, lft_param_pres = List.split all_lft_params_and_pres in
    let all_lft_params = List.flatten all_lft_params in
    let lft_param_pres = List.flatten lft_param_pres in
    let lft_params0, lft_params1 = List.split lft_params01 in
    let tparams01, all_tparams_and_pres =
      List.split
        (List.map2
           (fun ((x, bounds) as x_with_bounds) variance ->
             if variance = VarianceRd.Invariant then ((x, x), ([ x_with_bounds ], []))
             else
               let x0 = x ^ "0" in
               let x1 = x ^ "1" in
               ( (x0, x1),
                 ( [ (x0, bounds); (x1, bounds) ],
                   match variance with
                   | Covariant ->
                       [
                         ExprAsn
                           ( adt_def_loc,
                             CallExpr
                               ( adt_def_loc,
                                 "is_subtype_of",
                                 [
                                   IdentTypeExpr (adt_def_loc, None, x0);
                                   IdentTypeExpr (adt_def_loc, None, x1);
                                 ],
                                 [],
                                 [],
                                 Static ) );
                       ]
                   | Contravariant ->
                       [
                         ExprAsn
                           ( adt_def_loc,
                             CallExpr
                               ( adt_def_loc,
                                 "is_subtype_of",
                                 [
                                   IdentTypeExpr (adt_def_loc, None, x1);
                                   IdentTypeExpr (adt_def_loc, None, x0);
                                 ],
                                 [],
                                 [],
                                 Static ) );
                       ]
                   | _ -> [] ) ))
           tparams tparam_variances)
    in
    let all_tparams, tparam_pres = List.split all_tparams_and_pres in
    let all_tparams = List.flatten all_tparams in
    let tparam_pres = List.flatten tparam_pres in
    let tparams0, tparams1 = List.split tparams01 in
    let vf_tparams = unbounded_tparams all_lft_params @ all_tparams in
    let vf_tparams0 = lft_params0 @ tparams0 in
    let tparams_targs0 =
      List.map (fun x -> IdentTypeExpr (adt_def_loc, None, x)) vf_tparams0
    in
    let vf_tparams1 = lft_params1 @ tparams1 in
    let tparams_targs1 =
      List.map (fun x -> IdentTypeExpr (adt_def_loc, None, x)) vf_tparams1
    in
    let pre =
      CallExpr
        ( adt_def_loc,
          name ^ "_own",
          tparams_targs0,
          [],
          [ VarPat (adt_def_loc, "t"); VarPat (adt_def_loc, "v") ],
          if vf_tparams = [] then PredFamCall else PredCtorCall )
    in
    let pre =
      List.fold_left (fun a1 a2 -> Sep (adt_def_loc, a1, a2)) pre lft_param_pres
    in
    let pre =
      List.fold_left (fun a1 a2 -> Sep (adt_def_loc, a1, a2)) pre tparam_pres
    in
    let pre = add_type_interp_asns adt_def_loc (List.map fst all_tparams) pre in
    let tp0 =
      StructTypeExpr (adt_def_loc, Some name, None, [], tparams_targs0)
    in
    let tp1 =
      StructTypeExpr (adt_def_loc, Some name, None, [], tparams_targs1)
    in
    let init_for_fd ({ name = f; ty; vis; loc = l } : Mir.field_def_tr) =
      let e =
        match ty.vf_ty with
        | PtrTypeExpr (_, _) | RustRefTypeExpr (_, _, _, _) ->
            CastExpr
              ( l,
                ManifestTypeExpr (adt_def_loc, PtrType Void),
                Select (l, Var (l, "v"), f) )
        | _ ->
            CallExpr
              ( l,
                "upcast",
                [],
                [],
                [ LitPat (Select (l, Var (l, "v"), f)) ],
                Static )
      in
      (Some (l, f), e)
    in
    let upcast_call =
      CallExpr
        ( adt_def_loc,
          "upcast",
          [ tp0; tp1 ],
          [],
          [ LitPat (Var (adt_def_loc, "v")) ],
          Static )
    in
    let upcast_expr =
      CastExpr
        ( adt_def_loc,
          tp1,
          InitializerList (adt_def_loc, List.map init_for_fd fds_no_zst) )
    in
    let post =
      CallExpr
        ( adt_def_loc,
          name ^ "_own",
          tparams_targs1,
          [],
          [ LitPat (Var (adt_def_loc, "t")); LitPat upcast_expr ],
          if vf_tparams = [] then PredFamCall else PredCtorCall )
    in
    let post = add_type_interp_asns adt_def_loc (List.map fst all_tparams) post in
    ( [
        Func
          ( adt_def_loc,
            Lemma
              ( false
                (*indicates whether an axiom should be generated for this lemma*),
                None (*trigger*) ),
            vf_tparams (*type parameters*),
            None (*return type*),
            name ^ "_own_mono",
            [],
            false (*nonghost_callers_only*),
            (None, None)
            (*implemented function type, with function type type arguments and function type arguments*),
            Some (pre, ("result", post)) (*contract*),
            false (*terminates*),
            None (*body*),
            false (*virtual*),
            [] (*overrides*) );
      ],
      let post =
        ExprAsn
          ( adt_def_loc,
            Operation (adt_def_loc, Eq, [ upcast_call; upcast_expr ]) )
      in
      [
        Func
          ( adt_def_loc,
            Lemma
              ( false
                (*indicates whether an axiom should be generated for this lemma*),
                None (*trigger*) ),
            vf_tparams (*type parameters*),
            None (*return type*),
            name ^ "_upcast",
            [ (tp0, "v") ],
            false (*nonghost_callers_only*),
            (None, None)
            (*implemented function type, with function type type arguments and function type arguments*),
            Some (EmpAsn adt_def_loc, ("result", post)) (*contract*),
            false (*terminates*),
            Some
              ( [
                  ExprStmt
                    (CallExpr
                       ( adt_def_loc,
                         "#assume",
                         [],
                         [],
                         [ LitPat (False adt_def_loc) ],
                         Static ));
                ],
                adt_def_loc )
            (*body*),
            false (*virtual*),
            [] (*overrides*) );
      ] )

  let gen_sync_proof_oblig adt_def_loc name lft_params tparams =
    let open Ast in
    let vf_tparams = unbounded_tparams lft_params @ tparams in
    let tparams_targs =
      List.map (fun (x, _) -> IdentTypeExpr (adt_def_loc, None, x)) vf_tparams
    in
    let params = [ (IdentTypeExpr (adt_def_loc, None, "thread_id_t"), "t1") ] in
    let pre =
      Sep
        ( adt_def_loc,
          mk_sync_asn adt_def_loc (Ast.StructTypeExpr (adt_def_loc, Some name, None, [], tparams_targs)),
          CoefAsn
            ( adt_def_loc,
              DummyPat,
              CallExpr
                ( adt_def_loc,
                  name ^ "_share",
                  tparams_targs,
                  [],
                  [
                    VarPat (adt_def_loc, "k");
                    VarPat (adt_def_loc, "t0");
                    VarPat (adt_def_loc, "l");
                  ],
                  if vf_tparams = [] then PredFamCall else PredCtorCall ) ) )
    in
    let pre =
      add_type_interp_asns adt_def_loc (List.map fst tparams) pre
    in
    let post =
      CoefAsn
        ( adt_def_loc,
          DummyPat,
          CallExpr
            ( adt_def_loc,
              name ^ "_share",
              tparams_targs,
              [],
              [
                LitPat (Var (adt_def_loc, "k"));
                LitPat (Var (adt_def_loc, "t1"));
                LitPat (Var (adt_def_loc, "l"));
              ],
              if vf_tparams = [] then PredFamCall else PredCtorCall ) )
    in
    let post = add_type_interp_asns adt_def_loc (List.map fst tparams) post in
    Func
      ( adt_def_loc,
        Lemma
          ( false
            (*indicates whether an axiom should be generated for this lemma*),
            None (*trigger*) ),
        vf_tparams (*type parameters*),
        None (*return type*),
        name ^ "_sync",
        params,
        false (*nonghost_callers_only*),
        (None, None)
        (*implemented function type, with function type type arguments and function type arguments*),
        Some (pre, ("result", post)) (*contract*),
        false (*terminates*),
        None (*body*),
        false (*virtual*),
        [] (*overrides*) )

  let gen_share_proof_obligs adt_def lft_params tparams_with_bounds send_tparams sync_preds
      =
    let open Ast in
    let* adt_kind = Mir.decl_mir_adt_kind adt_def in
    match adt_kind with
    | Mir.Enum | Mir.Union ->
        failwith "Todo: Gen proof obligs for Enum or Union"
    | Mir.Struct ->
        let adt_def_loc = AstAux.decl_loc adt_def in
        let tparams = List.map fst tparams_with_bounds in
        let vf_tparams = unbounded_tparams lft_params @ tparams_with_bounds in
        let tparams_targs =
          List.map
            (fun (x, _) -> IdentTypeExpr (adt_def_loc, None, x))
            vf_tparams
        in
        let* name =
          Option.to_result ~none:(`GenAdtProofObligs "Failed to get ADT name")
            (AstAux.decl_name adt_def)
        in
        let lft_param n =
          (IdentTypeExpr (adt_def_loc, None (*package name*), "lifetime_t"), n)
        in
        let thread_id_param n =
          (IdentTypeExpr (adt_def_loc, None (*package name*), "thread_id_t"), n)
        in
        let void_ptr_param n =
          (ManifestTypeExpr (adt_def_loc, PtrType Void), n)
        in
        let lpat_var n = LitPat (Var (adt_def_loc, n)) in
        (*TY-SHR-MONO*)
        let params =
          [
            lft_param "k";
            lft_param "k1";
            thread_id_param "t";
            void_ptr_param "l";
          ]
        in
        let lft_inc_asn =
          Operation
            ( adt_def_loc,
              Eq,
              [
                CallExpr
                  ( adt_def_loc,
                    "lifetime_inclusion",
                    (*type arguments*) [],
                    (*indices*) [],
                    (*arguments*)
                    List.map lpat_var [ "k1"; "k" ],
                    Static );
                True adt_def_loc;
              ] )
        in
        let shr_asn lft_n =
          CoefAsn
            ( adt_def_loc,
              DummyPat,
              CallExpr
                ( adt_def_loc,
                  name ^ "_share",
                  (*type arguments*) tparams_targs,
                  (*indices*) [],
                  (*arguments*)
                  List.map lpat_var [ lft_n; "t"; "l" ],
                  if tparams_targs = [] then PredFamCall else PredCtorCall ) )
        in
        let pre =
          add_type_interp_asns adt_def_loc tparams
            (add_send_asns adt_def_loc send_tparams
               (Sep (adt_def_loc, lft_inc_asn, shr_asn "k")))
        in
        let post = add_type_interp_asns adt_def_loc tparams (shr_asn "k1") in
        let share_mono_po =
          Func
            ( adt_def_loc,
              Lemma
                ( false
                  (*indicates whether an axiom should be generated for this lemma*),
                  None (*trigger*) ),
              vf_tparams (*type parameters*),
              None (*return type*),
              name ^ "_share_mono",
              params,
              false (*nonghost_callers_only*),
              (None, None)
              (*implemented function type, with function type type arguments and function type arguments*),
              Some (pre, ("result", post)) (*contract*),
              false (*terminates*),
              None (*body*),
              false (*virtual*),
              [] (*overrides*) )
        in
        (*TY-SHR*)
        let params =
          [ lft_param "k"; thread_id_param "t"; void_ptr_param "l" ]
        in
        let atomic_mask_token mask =
          CallExpr
            ( adt_def_loc,
              "atomic_mask",
              (*type arguments*) [],
              (*indices*) [],
              (*arguments*)
              [ lpat_var mask ],
              Static )
        in
        let fbor_pred =
          CallExpr
            ( adt_def_loc,
              "full_borrow",
              (*type arguments*) [],
              (*indices*) [],
              (*arguments*)
              [
                lpat_var "k";
                LitPat
                  (CallExpr
                     ( adt_def_loc,
                       name ^ "_full_borrow_content",
                       (*type arguments*) tparams_targs,
                       (*indices*) [],
                       (*arguments*)
                       List.map lpat_var [ "t"; "l" ],
                       Static ));
              ],
              Static )
        in
        let lft_token coef_pat =
          CoefAsn
            ( adt_def_loc,
              coef_pat,
              CallExpr
                ( adt_def_loc,
                  "lifetime_token",
                  (*type arguments*) [],
                  (*indices*) [],
                  (*arguments*)
                  [ lpat_var "k" ],
                  Static ) )
        in
        let (Some pre) =
          AstAux.list_to_sep_conj
            (List.map
               (fun asn -> (adt_def_loc, asn))
               [
                 atomic_mask_token "MaskTop";
                 fbor_pred;
                 lft_token (VarPat (adt_def_loc, "q"));
                 Operation
                   ( adt_def_loc,
                     Eq,
                     [
                       CallExpr
                         ( adt_def_loc,
                           "ref_origin",
                           [],
                           [],
                           [ LitPat (Var (adt_def_loc, "l")) ],
                           Static );
                       Var (adt_def_loc, "l");
                     ] );
               ])
            None
        in
        let pre =
          add_type_interp_asns adt_def_loc tparams
            (add_send_asns adt_def_loc send_tparams pre)
        in
        let share_pred l =
          CoefAsn
            ( adt_def_loc,
              DummyPat,
              CallExpr
                ( adt_def_loc,
                  name ^ "_share",
                  (*type arguments*) tparams_targs,
                  (*indices*) [],
                  (*arguments*)
                  List.map lpat_var [ "k"; "t"; l ],
                  if tparams_targs = [] then PredFamCall else PredCtorCall ) )
        in
        let (Some post) =
          AstAux.list_to_sep_conj
            (List.map
               (fun asn -> (adt_def_loc, asn))
               [
                 atomic_mask_token "MaskTop";
                 share_pred "l";
                 lft_token (lpat_var "q");
               ])
            None
        in
        let post = add_type_interp_asns adt_def_loc tparams post in
        let share_po =
          Func
            ( adt_def_loc,
              Lemma
                ( false
                  (*indicates whether an axiom should be generated for this lemma*),
                  None (*trigger*) ),
              vf_tparams (*type parameters*),
              None (*return type*),
              name ^ "_share_full",
              params,
              false (*nonghost_callers_only*),
              (None, None)
              (*implemented function type, with function type type arguments and function type arguments*),
              Some (pre, ("result", post)) (*contract*),
              false (*terminates*),
              None (*body*),
              false (*virtual*),
              [] (*overrides*) )
        in
        (* init_ref_S *)
        let ref_init_perm =
          CallExpr
            ( adt_def_loc,
              "ref_init_perm",
              [],
              [],
              [ lpat_var "p"; VarPat (adt_def_loc, "x") ],
              Static )
        in
        let pre_shr_asn =
          CoefAsn
            ( adt_def_loc,
              DummyPat,
              CallExpr
                ( adt_def_loc,
                  name ^ "_share",
                  (*type arguments*) tparams_targs,
                  (*indices*) [],
                  (*arguments*)
                  [
                    VarPat (adt_def_loc, "k");
                    VarPat (adt_def_loc, "t");
                    lpat_var "x";
                  ],
                  if tparams_targs = [] then PredFamCall else PredCtorCall ) )
        in
        let (Some pre) =
          AstAux.list_to_sep_conj
            (List.map
               (fun asn -> (adt_def_loc, asn))
               [
                 atomic_mask_token "Nlft";
                 ref_init_perm;
                 pre_shr_asn;
                 lft_token (VarPat (adt_def_loc, "q"));
               ])
            None
        in
        let pre =
          add_type_interp_asns adt_def_loc tparams
            (add_send_asns adt_def_loc send_tparams pre)
        in
        let post_shr_asn =
          CoefAsn
            ( adt_def_loc,
              DummyPat,
              CallExpr
                ( adt_def_loc,
                  name ^ "_share",
                  (*type arguments*) tparams_targs,
                  (*indices*) [],
                  (*arguments*)
                  [ lpat_var "k"; lpat_var "t"; lpat_var "p" ],
                  if tparams_targs = [] then PredFamCall else PredCtorCall ) )
        in
        let ref_initialized_asn =
          CoefAsn
            ( adt_def_loc,
              DummyPat,
              CallExpr
                ( adt_def_loc,
                  "frac_borrow",
                  [],
                  [],
                  [
                    lpat_var "k";
                    LitPat
                      (CallExpr
                         ( adt_def_loc,
                           "ref_initialized_",
                           [],
                           [],
                           [ lpat_var "p" ],
                           Static ));
                  ],
                  Static ) )
        in
        let (Some post) =
          AstAux.list_to_sep_conj
            (List.map
               (fun asn -> (adt_def_loc, asn))
               [
                 atomic_mask_token "Nlft";
                 lft_token (lpat_var "q");
                 post_shr_asn;
                 ref_initialized_asn;
               ])
            None
        in
        let post = add_type_interp_asns adt_def_loc tparams post in
        let init_ref_po =
          Func
            ( adt_def_loc,
              Lemma
                ( false
                  (*indicates whether an axiom should be generated for this lemma*),
                  None (*trigger*) ),
              vf_tparams (*type parameters*),
              None (*return type*),
              qualified_derived_name "init_ref_%s" name,
              [
                ( PtrTypeExpr
                    ( adt_def_loc,
                      StructTypeExpr
                        (adt_def_loc, Some name, None, [], tparams_targs) ),
                  "p" );
              ],
              false (*nonghost_callers_only*),
              (None, None)
              (*implemented function type, with function type type arguments and function type arguments*),
              Some (pre, ("result", post)) (*contract*),
              false (*terminates*),
              None (*body*),
              false (*virtual*),
              [] (*overrides*) )
        in
        let sync_pos =
          match sync_preds with
          | None -> []
          | Some sync_preds ->
              [
                gen_sync_proof_oblig adt_def_loc name lft_params tparams_with_bounds
              ]
        in
        Ok ([ share_mono_po; share_po; init_ref_po ] @ sync_pos)

  type trait_impl = {
    trait_impl_cpn : TraitImplRd.t;
    loc : Ast.loc;
    is_unsafe : bool;
    is_negative : bool;
    of_trait : string;
    gen_args : Vf_mir_decoder.generic_arg list;
    self_ty : string;
    generics : Vf_mir_decoder.generic_param_def list;
    clauses : Vf_mir_decoder.clause list;
    items : D.trait_impl_item list;
  }

  let sep loc = function
    | [] -> Ast.True loc
    | x :: xs -> List.fold_left (fun a1 a2 -> Ast.Sep (loc, a1, a2)) x xs

  let default_struct_own (loc : Ast.loc) (fds : Mir.field_def_tr list)
      (t : string) (v : string) =
    let field_own_asns =
      fds
      |> List.map @@ fun (fd : Mir.field_def_tr) ->
         let interp = fd.ty.interp in
         match
           interp.own
             (Ast.Var (loc, "t"))
             (Ast.Select (loc, Ast.Var (loc, "v"), fd.name))
         with
         | Ok asn -> asn
         | Error msg ->
             Ast.static_error loc
               (Printf.sprintf
                  "Error while building default .own predicate conjunct for \
                   field %s: %s"
                  fd.name msg)
               None
    in
    sep loc field_own_asns

  let pointer_within_limits_asn loc l =
    Ast.Operation
      ( loc,
        Eq,
        [
          Ast.CallExpr
            (loc, "pointer_within_limits", [], [], [ Ast.LitPat l ], Ast.Static);
          Ast.True loc;
        ] )

  let default_struct_share (loc : Ast.loc) (fds : Mir.field_def_tr list)
      (k : string) (t : string) (l : string) =
    let field_share_asns =
      fds
      |> List.map @@ fun (fd : Mir.field_def_tr) ->
         let interp = fd.ty.interp in
         let lf =
           Ast.AddressOf (loc, Read (loc, Ast.Var (loc, "l"), fd.name))
         in
         match interp.shr (Ast.Var (loc, "k")) (Ast.Var (loc, "t")) lf with
         | Ok asn -> Ast.Sep (loc, pointer_within_limits_asn loc lf, asn)
         | Error msg ->
             Ast.static_error loc
               (Printf.sprintf
                  "Error while building default .share predicate conjunct for \
                   field %s: %s"
                  fd.name msg)
               None
    in
    sep loc field_share_asns

  let translate_adt_def target_triple pointer_width
      (ghost_decl_map : (string * Ast.decl) list)
      (ghost_decls : Ast.decl list) (trait_impls : trait_impl list)
      (adt_def_cpn : AdtDefRd.t) =
    let open AdtDefRd in
    let id_cpn = id_get adt_def_cpn in
    let def_path = translate_adt_def_id @@ D.decode_adt_def_id id_cpn in
    if TrName.is_from_std_lib def_path then Ok None
    else
      let name = TrName.translate_def_path def_path in
      let* generics =
        hir_generics_get adt_def_cpn
        |> HirGenericsRd.params_get_list
        |> ListAux.try_map @@ fun param_cpn ->
           let* l =
             translate_span_data (HirGenericParamRd.span_get param_cpn)
           in
           let name =
             match
               HirGenericParamRd.name_get param_cpn |> HirGenericParamNameRd.get
             with
             | Plain ident -> IdentRd.name_get ident |> SymbolRd.name_get
             | Fresh _ ->
                 raise
                   (Ast.StaticError
                      ( l,
                        "Structs with inferred type parameters are not yet \
                         supported",
                        None ))
           in
           match
             HirGenericParamRd.kind_get param_cpn |> HirGenericParamKindRd.get
           with
           | Lifetime -> Ok (`Lifetime name)
           | Type -> Ok (`Type name)
           | Const -> Ok (`Const name)
      in
      (* Type and const parameters are kept in declaration order, which is the order
         in which rustc supplies the corresponding generic arguments at use sites. *)
      let tparams =
        Util.flatmap (function (`Type x | `Const x) -> [ x ] | _ -> []) generics
      in
      let type_tparams =
        Util.flatmap (function `Type x -> [ x ] | _ -> []) generics
      in
      let tparams_with_bounds =
        generics |> Util.flatmap @@ function
          | `Type x -> [ (x, { Ast.sized = Verifast0.tparam_is_uppercase x }) ]
          | `Const x -> [ (x, { Ast.sized = false }) ]
          | _ -> []
      in
      let lft_params =
        Util.flatmap (function `Lifetime x -> [ x ] | _ -> []) generics
      in
      let vf_tparams = lft_params @ tparams in
      let vf_tparams_with_bounds = Ast.unbounded_tparams lft_params @ tparams_with_bounds in
      let variances = variances_get_list adt_def_cpn in
      let variants_cpn = variants_get_list adt_def_cpn in
      let decoded_variants = List.map D.decode_variant_def variants_cpn in
      (* The variants, with some fields F such that sizeof(F) = 0 && F.ty.OWN = True filtered out
       * The latter condition is exploited in gen_drop_contract.
       *)
      let decoded_variants_no_zst = decoded_variants |> List.map @@ function ({span; name; fields}: D.variant_def) ->
        let fields = fields |> List.filter (function ({ty={kind=Adt {id={name=("std::marker::PhantomData"|"core::marker::PhantomData")}}}}: D.variant_def_field_def) -> false | _ -> true) in
        ({span; name; fields}: D.variant_def)
      in
      let* variants = ListAux.try_map translate_variant_def decoded_variants in
      let* variants_no_zst = ListAux.try_map translate_variant_def decoded_variants_no_zst in
      let span_cpn = def_span_get adt_def_cpn in
      let* def_loc = translate_span_data span_cpn in
      let clauses =
        clauses_get_list adt_def_cpn
        |> List.map D.decode_clause
        |> List.map decode_clause
      in
      let sized_tparams = compute_sized_tparams clauses in
      let unsized_tparams = List.filter (fun x -> not (List.mem x sized_tparams)) type_tparams in
      let send_tparams = compute_send_tparams clauses in
      let tparams_targs =
        List.map (fun x -> Ast.IdentTypeExpr (def_loc, None, x)) vf_tparams
      in
      let vis_cpn = vis_get adt_def_cpn in
      let* vis = translate_visibility @@ D.decode_visibility vis_cpn in
      let is_local = is_local_get adt_def_cpn in
      let kind_cpn = kind_get adt_def_cpn in
      let* kind, fds, fds_no_zst, def, aux_decls =
        match AdtKindRd.get kind_cpn with
        | StructKind ->
            let [ variant_def ] = variants in
            let fds = variant_def.fields in
            let [ variant_def_no_zst ] = variants_no_zst in
            let fds_no_zst = variant_def_no_zst.fields in
            let field_defs_no_zst = List.map translate_to_vf_field_def fds_no_zst in
            let concrete_guard_attrs =
              if not (has_concrete_guard_layout_get adt_def_cpn) then []
              else begin
                let concrete_guard_def_path = concrete_guard_def_path_get adt_def_cpn in
                let source_def_path_hash = concrete_guard_def_path_hash_get adt_def_cpn in
                let size_bytes = Stdint.Uint64.to_string (concrete_guard_size_bytes_get adt_def_cpn) in
                let align_bytes = Stdint.Uint64.to_string (concrete_guard_align_bytes_get adt_def_cpn) in
                let field_offsets =
                  concrete_guard_field_offsets_get_list adt_def_cpn
                in
                let field_sizes =
                  concrete_guard_field_sizes_get_list adt_def_cpn
                in
                let exact_field_shape = match fds with
                  | [ { Mir.name = "src"; ty = { vf_ty = Ast.PtrTypeExpr (_, Ast.ManifestTypeExpr (_, Ast.Int (Unsigned, FixedWidthRank 3))); _ }; _ };
                      { Mir.name = "dst"; ty = { vf_ty = Ast.PtrTypeExpr (_, Ast.ManifestTypeExpr (_, Ast.Int (Unsigned, FixedWidthRank 3))); _ }; _ };
                      { Mir.name = "len"; ty = { vf_ty = Ast.ManifestTypeExpr (_, Ast.Int (Unsigned, PtrRank)); _ }; _ } ] -> true
                  | _ -> false
                in
                if concrete_guard_def_path <> def_path
                    || target_triple <> "x86_64-unknown-linux-gnu" || pointer_width <> 64
                    || vf_tparams <> [] || not exact_field_shape
                    || List.length field_offsets <> 3 || List.length field_sizes <> 3
                    || String.length source_def_path_hash = 0
                then
                  Ast.static_error def_loc
                    "Compiler concrete guard layout does not match the qualified u64 guard shape"
                    None;
                [Ast.RustConcreteGuardLayout {
                  source_def_path = concrete_guard_def_path;
                  source_def_path_hash;
                  target_triple;
                  pointer_width;
                  size_bytes;
                  align_bytes;
                  field_offsets;
                  field_sizes;
                }]
              end
            in
            let struct_decl =
              Ast.Struct
                ( def_loc,
                  name,
                  vf_tparams,
                  Left
                    ( (*base_spec list*) [],
                      (*field list*) field_defs_no_zst,
                      (*instance_pred_decl list*) [],
                      (*is polymorphic*) false ),
                  (*struct_attr list*)
                  (if is_repr_c_get adt_def_cpn then [ Ast.ReprC ] else []) @ concrete_guard_attrs )
            in
            let struct_typedef_aux =
              Ast.TypedefDecl
                ( def_loc,
                  StructTypeExpr (def_loc, Some name, None, [], tparams_targs),
                  name,
                  lft_params @ tparams )
            in
            Ok (Mir.Struct, fds, fds_no_zst, struct_decl, [struct_typedef_aux])
        | EnumKind ->
            let _, simple_name = split_item_name name in
            let ctors =
              (* VeriFast does not support zero-ctor inductives, so add a dummy ctor. *)
              if variants = [] then [ Ast.Ctor (def_loc, simple_name ^ "::Dummy", []) ]
              else
                variants
                |> List.map @@ fun Mir.{ loc; name = variant_name; fields } ->
                   let ps =
                     fields
                     |> List.map @@ fun Mir.{ name; ty } -> (name, ty.vf_ty)
                   in
                   Ast.Ctor (loc, simple_name ^ "::" ^ variant_name, ps)
            in
            let decl = Ast.Inductive (def_loc, name, vf_tparams, ctors) in
            Ok (Mir.Enum, [], [], decl, Rust_parser.own_pred_decls_for_enum def_loc name ctors vf_tparams)
        | UnionKind -> failwith "Todo: AdtDef::Union"
        | Undefined _ -> Error (`TrAdtDef "Unknown ADT kind")
      in
      let user_provided_type_pred_defs_for p =
        let rec iter modulePath decls =
          if not (String.starts_with ~prefix:modulePath name) then []
          else
            decls
            |> Util.flatmap @@ function
               | Ast.TypePredDef
                   ( _,
                     _,
                     ( IdentTypeExpr (_, None, sn)
                     | ConstructedTypeExpr (_, sn, _) ),
                     p',
                     body )
                 when String.ends_with ~suffix:sn name
                      && (if modulePath = "" then sn else modulePath ^ "::" ^ sn)
                         = name
                      && p' = p ->
                   [ body ]
               | ModuleDecl (loc, moduleName, _, decls') ->
                   let modulePath =
                     if modulePath = "" then moduleName
                     else modulePath ^ "::" ^ moduleName
                   in
                   iter modulePath decls'
               | _ -> []
        in
        iter "" ghost_decls
      in
      let* full_bor_content, proof_obligs, delayed_proof_obligs, aux_decls' =
        if is_local && AdtKindRd.get kind_cpn = StructKind then (
          let user_provided_own_defs = user_provided_type_pred_defs_for "own" in
          let user_provided_share_defs =
            user_provided_type_pred_defs_for "share"
          in
          let has_public_fields =
            List.exists (fun x -> x.Mir.vis = Public) fds
          in
          if
            has_public_fields
            && (user_provided_own_defs <> [] || user_provided_share_defs <> [])
          then
            Ast.static_error def_loc
              "User-provided .own or .share predicates for structs with public \
               fields are not yet supported"
              None;
          let field_types =
            decoded_variants
            |> Util.flatmap @@ fun ({fields}: D.variant_def) ->
               fields |> List.map @@ fun ({ty}: D.variant_def_field_def) ->
                  decode_ty ty
          in
          let field_types_no_zst =
            decoded_variants_no_zst
            |> Util.flatmap @@ fun ({fields}: D.variant_def) ->
               fields |> List.map @@ fun ({ty}: D.variant_def_field_def) ->
                  decode_ty ty
          in
          let send_impls =
            trait_impls
            |> List.filter (fun { of_trait; self_ty } ->
                    (of_trait = "std::marker::Send"
                    || of_trait = "core::marker::Send")
                    && self_ty = name)
          in
          let sync_impls =
            trait_impls
            |> List.filter (fun { of_trait; self_ty } ->
                    (of_trait = "std::marker::Sync"
                    || of_trait = "core::marker::Sync")
                    && self_ty = name)
          in
          (* If send_preds = None, it means this ADT is never Send.
             If send_preds = Some xs, then xs is a list of type parameters such that if any of them are not Send, then this ADT is not Send.
             Note that Some [] is always a valid value for send_preds, and that if Some xs is a valid value, then Some (xs @ ys) is also a valid value.
             Similarly, if sync_preds = None, it means this ADT is never Sync.
             If sync_preds = Some xs, then xs is a list of type parameters such that if any of them are not Sync, then this ADT is not Sync.
             xs may contain duplicates. *)
          let send_preds, sync_preds =
            (* Computes the map from impl generic params to ADT generic params *)
            let get_impl_generic_param_map loc trait_impl_cpn =
              let impl_generics =
                TraitImplRd.generics_get_list trait_impl_cpn
                |> List.map decode_generic_param
              in
              let impl_generic_type_params =
                List.filter_map
                  (function `Type x -> Some x | _ -> None)
                  impl_generics
              in
              let adt_generic_type_params =
                List.filter_map
                  (function `Type x -> Some x | _ -> None)
                  generics
              in
              let impl_generic_lifetime_params =
                List.filter_map
                  (function `Lifetime x -> Some x | _ -> None)
                  impl_generics
              in
              let adt_generic_lifetime_params =
                List.filter_map
                  (function `Lifetime x -> Some x | _ -> None)
                  generics
              in
              let impl_type_param_map =
                match
                  Util.zip impl_generic_type_params adt_generic_type_params
                with
                | Some bs -> bs
                | None ->
                    Ast.static_error loc
                      "Number of impl generic type parameters does not match \
                       number of ADT generic type parameters"
                      None
              in
              let impl_lifetime_param_map =
                match
                  Util.zip impl_generic_lifetime_params
                    adt_generic_lifetime_params
                with
                | Some bs -> bs
                | None ->
                    Ast.static_error loc
                      "Number of impl generic lifetime parameters does not \
                       match number of ADT generic lifetime parameters"
                      None
              in
              let [ `Type (`Adt (_, _, self_ty_gen_args)) ] =
                TraitImplRd.gen_args_get_list trait_impl_cpn
                |> List.map D.decode_generic_arg
                |> List.map decode_generic_arg
              in
              (match Util.zip impl_generics self_ty_gen_args with
              | None ->
                  Ast.static_error loc
                    "Number of trait self type generic arguments does not \
                     match impl generic parameter list"
                    None
              | Some bs -> (
                  bs
                  |> List.iter @@ function
                     | `Type x, `Type (`Param y) when x = y -> ()
                     | `Lifetime x, `Lifetime y when x = y -> ()
                     | _ ->
                         Ast.static_error loc
                           "Trait self type generic arguments do not match \
                            impl generic parameter list"
                           None));
              (impl_type_param_map, impl_lifetime_param_map)
            in
            let check_impl_generics_matches_adt loc trait_impl_cpn =
              let impl_generics =
                TraitImplRd.generics_get_list trait_impl_cpn
                |> List.map decode_generic_param
              in
              if impl_generics <> generics then
                Ast.static_error loc
                  "Impl generic parameter names must match ADT generic \
                   parameter names"
                  None;
              let [ `Type (`Adt (_, _, self_ty_gen_args)) ] =
                TraitImplRd.gen_args_get_list trait_impl_cpn
                |> List.map D.decode_generic_arg
                |> List.map decode_generic_arg
              in
              match Util.zip impl_generics self_ty_gen_args with
              | None ->
                  Ast.static_error loc
                    "Number of trait self type generic arguments does not \
                     match impl generic parameter list"
                    None
              | Some bs -> (
                  bs
                  |> List.iter @@ function
                     | `Type x, `Type (`Param y) when x = y -> ()
                     | `Lifetime x, `Lifetime y when x = y -> ()
                     | _ ->
                         Ast.static_error loc
                           "Trait self type generic arguments do not match \
                            impl generic parameter list"
                           None)
            in
            let check_impl_covers_adt { loc; trait_impl_cpn } =
              check_impl_generics_matches_adt loc trait_impl_cpn;
              let impl_clauses =
                TraitImplRd.clauses_get_list trait_impl_cpn
                |> List.map D.decode_clause
                |> List.map decode_clause
              in
              impl_clauses
              |> List.iter @@ fun impl_clause ->
                 let same_adt_constraint candidate =
                   match impl_clause, candidate with
                   | `Trait (name1, args1, _), `Trait (name2, args2, _) ->
                       name1 = name2 && args1 = args2
                   | _ -> impl_clause = candidate
                 in
                 if not (List.exists same_adt_constraint clauses) then
                   let string_of_clauses clauses =
                     String.concat ", " (List.map string_of_clause clauses)
                   in
                   Ast.static_error loc
                     (Printf.sprintf
                        "Trait generic parameter constraint %s does not match \
                         any of the ADT generic parameter constraints %s"
                        (string_of_clause impl_clause)
                        (string_of_clauses clauses))
                     None
            in
            let get_impl_clauses { loc; trait_impl_cpn } =
              let impl_type_param_map, impl_lifetime_param_map =
                get_impl_generic_param_map loc trait_impl_cpn
              in
              let impl_clauses =
                TraitImplRd.clauses_get_list trait_impl_cpn
                |> List.map D.decode_clause
                |> List.map decode_clause
              in
              impl_clauses
              |> Util.flatmap (function
                   | `Trait (trait_name', `Type (`Param x) :: _, _) ->
                       [
                         ( List.assoc x impl_type_param_map,
                           canonicalize_item_name trait_name' );
                       ]
                   | _ -> [])
            in
            let preds_union preds1 preds2 =
              match (preds1, preds2) with
              | Some xs1, Some xs2 ->
                  Some (xs1 @ xs2) (* May introduce duplicates *)
              | _ -> None
            in
            let preds_intersection preds1 preds2 =
              match (preds1, preds2) with
              | Some xs1, Some xs2 ->
                  Some (List.filter (fun x -> List.mem x xs2) xs1)
              | Some xs1, None -> Some xs1
              | None, Some xs2 -> Some xs2
              | None, None -> None
            in
            let rec send_preds_of = function
              | `Param x -> Some [ x ]
              | `RawPtr -> None
              | `Adt ("std::ptr::NonNull", _, _) -> None
              | `Adt
                  ( ( "std::cell::UnsafeCell" | "std::marker::PhantomData"
                    | "std::boxed::Box" | "std::option::Option" ),
                    _,
                    [ `Type tp ] ) ->
                  send_preds_of tp
              | _ -> Some []
              (* Conservatively assume the type is always Send. TODO: Make this more precise. *)
            in
            let rec sync_preds_of = function
              | `Param x -> Some [ x ]
              | `RawPtr -> None
              | `Adt ("std::ptr::NonNull", _, _) -> None
              | `Adt ("std::cell::UnsafeCell", _, _) -> None
              | `Adt
                  ( ( "std::marker::PhantomData" | "std::boxed::Box"
                    | "std::option::Option" ),
                    _,
                    [ `Type tp ] ) ->
                  sync_preds_of tp
              | _ -> Some []
              (* Conservatively assume the type is always Sync. TODO: Make this more precise. *)
            in
            let send_preds =
              field_types
              |> List.fold_left
                   (fun preds ty -> preds_union preds (send_preds_of ty))
                   (Some [])
            in
            let negative_send_impls, positive_send_impls =
              send_impls |> List.partition (fun { is_negative } -> is_negative)
            in
            let send_preds =
              match send_preds with
              | None -> None
              | Some xs -> (
                  match negative_send_impls with
                  | [] -> Some xs
                  | impl :: _ ->
                      check_impl_covers_adt impl;
                      (* OK, this negative impl covers all instantiations of the ADT so it cancels out the implicit send *)
                      None)
            in
            let send_preds =
              send_preds
              |> Option.map @@ List.map @@ fun x -> (x, "std::marker::Send")
            in
            let send_preds =
              positive_send_impls
              |> List.fold_left
                   (fun preds trait_impl ->
                     preds_intersection preds (Some (get_impl_clauses trait_impl)))
                   send_preds
            in
            let sync_preds =
              field_types
              |> List.fold_left
                   (fun preds ty -> preds_union preds (sync_preds_of ty))
                   (Some [])
            in
            let negative_sync_impls, positive_sync_impls =
              sync_impls |> List.partition (fun { is_negative } -> is_negative)
            in
            let sync_preds =
              match sync_preds with
              | None -> None
              | Some xs -> (
                  match negative_sync_impls with
                  | [] -> Some xs
                  | impl :: _ ->
                      check_impl_covers_adt impl;
                      None)
            in
            let sync_preds =
              sync_preds
              |> Option.map @@ List.map @@ fun x -> (x, "std::marker::Sync")
            in
            let sync_preds =
              positive_sync_impls
              |> List.fold_left
                   (fun preds trait_impl ->
                     preds_intersection preds (Some (get_impl_clauses trait_impl)))
                   sync_preds
            in
            (send_preds, sync_preds)
          in
          let* full_bor_content =
            gen_adt_full_borrow_content kind name tparams lft_params variants_no_zst
              def_loc (match user_provided_own_defs with [ Right(_, Some _, _) ] -> true | _ -> false)
          in
          let variable_occurs_in_expr x e =
            let rec iter acc e =
              match e with
              | Ast.Var (_, y) when x = y -> true
              | _ -> Ast.expr_fold_open iter acc e
            in
            iter false e
          in
          let own_proof_obligs =
            match send_preds with
            | Some xs when
                match user_provided_own_defs with
                  [ Right ([ t; v ], _, body) ] -> variable_occurs_in_expr t body
                | _ -> false
              ->
                [
                  gen_send_proof_oblig def_loc name tparams vf_tparams_with_bounds
                ]
            | _ -> []
          in
          let own_variance_proof_obligs, upcast_lemmas =
            if
              user_provided_own_defs <> []
              && List.exists
                   (fun variance -> variance <> VarianceRd.Invariant)
                   variances
            then
              gen_own_variance_proof_oblig def_loc name lft_params tparams_with_bounds
                variances fds_no_zst
            else ([], [])
          in
          let own_proof_obligs = own_variance_proof_obligs @ own_proof_obligs in
          let* share_proof_obligs =
            if user_provided_share_defs <> [] then
              let sync_preds =
                match sync_preds with
                | None -> None
                | Some _ -> (
                    match user_provided_share_defs with
                    | [ Right ([ k; t; l ], _, body) ]
                      when not (variable_occurs_in_expr t body) ->
                        None
                    | _ -> sync_preds)
              in
              gen_share_proof_obligs def lft_params tparams_with_bounds send_tparams
                sync_preds
            else Ok []
          in
          let structTypeExpr = Ast.StructTypeExpr (def_loc, Some name, None, [], tparams_targs) in
          let type_pred_defs =
            (if user_provided_own_defs <> [] then []
             else
               [
                 (let inputParamCount, body =
                    if has_public_fields then
                      (None, default_struct_own def_loc fds_no_zst "t" "v")
                    else (Some 2, False def_loc)
                  in
                  Ast.TypePredDef
                    ( def_loc,
                      vf_tparams,
                      structTypeExpr,
                      "own",
                      Right ([ "t"; "v" ], inputParamCount, body) ));
               ])
            @ [
                Ast.TypePredDef
                  ( def_loc,
                    vf_tparams,
                    structTypeExpr,
                    "full_borrow_content",
                    Left (def_loc, name ^ "_full_borrow_content") );
              ]
            @
            if user_provided_share_defs <> [] then []
            else
              [
                (let inputParamCount, body =
                   if has_public_fields then
                     (None, default_struct_share def_loc fds_no_zst "k" "t" "v")
                   else (Some 3, True def_loc)
                 in
                 Ast.TypePredDef
                   ( def_loc,
                     vf_tparams,
                     structTypeExpr,
                     "share",
                     Right ([ "k"; "t"; "l" ], inputParamCount, body) ));
              ]
          in
          let delayed_proof_obligs =
            if user_provided_own_defs <> [] then
              let is_trivially_droppable =
                fds
                |> List.for_all @@ fun (fd : Mir.field_def_tr) ->
                   type_is_trivially_droppable fd.ty.vf_ty
              in
              if is_trivially_droppable || implements_drop_get adt_def_cpn then
                []
              else
                [
                  (fun adt_defs ->
                    gen_adt_drop_proof_oblig adt_defs def_loc name vf_tparams_with_bounds
                      (List.map
                         (fun (fd : Mir.field_def_tr) ->
                           (fd.loc, fd.name, fd.ty))
                         fds_no_zst));
                ]
            else []
          in
          let send_lemmas =
            let mk_send_lemma rhs =
              let post =
                Ast.Operation (def_loc, Eq, [
                  mk_send_expr def_loc structTypeExpr;
                  rhs
                ])
              in
              Ast.Func
                ( def_loc,
                  Lemma
                    ( true
                      (*indicates whether an axiom should be generated for this lemma*),
                      Some (mk_send_expr def_loc structTypeExpr)),
                  Ast.unbounded_tparams vf_tparams (*type parameters*),
                  None (*return type*),
                  qualified_derived_name "is_Send_%s_lemma" name,
                  [],
                  false (*nonghost_callers_only*),
                  (None, None)
                  (*implemented function type, with function type type arguments and function type arguments*),
                  Some (True def_loc, ("result", post)) (*contract*),
                  false (*terminates*),
                  Some
                    ( [
                        ExprStmt
                          (CallExpr
                            ( def_loc,
                              "#assume",
                              [],
                              [],
                              [ LitPat (False def_loc) ],
                              Static ));
                      ],
                      def_loc )
                  (*body*),
                  false (*virtual*),
                  [] (*overrides*) )
            in
            match send_preds with
              None -> [mk_send_lemma (Ast.False def_loc)]
            | Some xs ->
              let send_tparams =
                List.filter
                  (fun x ->
                    List.mem (x, "std::marker::Send") xs
                    || List.mem x send_tparams)
                  tparams
              in
              let sync_tparams =
                List.filter
                  (fun x -> List.mem (x, "std::marker::Sync") xs)
                  tparams
              in
              let rhs_conjuncts =
                List.map (mk_send_tparam_expr def_loc) send_tparams @
                List.map (mk_sync_tparam_expr def_loc) sync_tparams
              in
              if rhs_conjuncts = [] then [] else
              [mk_send_lemma (List.fold_left (fun e e1 -> Ast.Operation (def_loc, And, [e; e1])) (mk_send_expr def_loc structTypeExpr) rhs_conjuncts)]
          in
          let sync_lemmas =
            let mk_sync_lemma rhs =
              let post =
                Ast.Operation (def_loc, Eq, [
                  mk_sync_expr def_loc structTypeExpr;
                  rhs
                ])
              in
              Ast.Func
                ( def_loc,
                  Lemma
                    ( true
                      (*indicates whether an axiom should be generated for this lemma*),
                      Some (mk_sync_expr def_loc structTypeExpr)),
                  Ast.unbounded_tparams vf_tparams (*type parameters*),
                  None (*return type*),
                  qualified_derived_name "is_Sync_%s_lemma" name,
                  [],
                  false (*nonghost_callers_only*),
                  (None, None)
                  (*implemented function type, with function type type arguments and function type arguments*),
                  Some (True def_loc, ("result", post)) (*contract*),
                  false (*terminates*),
                  Some
                    ( [
                        ExprStmt
                          (CallExpr
                            ( def_loc,
                              "#assume",
                              [],
                              [],
                              [ LitPat (False def_loc) ],
                              Static ));
                      ],
                      def_loc )
                  (*body*),
                  false (*virtual*),
                  [] (*overrides*) )
            in
            match sync_preds with
              None -> [mk_sync_lemma (Ast.False def_loc)]
            | Some sync_preds ->
              let sync_tparams =
                List.filter
                  (fun x -> List.mem (x, "std::marker::Sync") sync_preds)
                  tparams
              in
              let rhs_conjuncts =
                List.map (mk_sync_tparam_expr def_loc) sync_tparams
              in
              if rhs_conjuncts = [] then [] else
              [mk_sync_lemma (List.fold_left (fun e e1 -> Ast.Operation (def_loc, And, [e; e1])) (mk_sync_expr def_loc structTypeExpr) rhs_conjuncts)]
          in
          let send_def_lemmas =
            if send_impls <> [] then [] else
            [
              let rhs =
                let rhs_conjuncts =
                  fds |> List.map (fun fd -> mk_send_expr def_loc fd.Mir.ty.Mir.vf_ty)
                in
                List.fold_left (fun e e1 -> Ast.Operation (def_loc, And, [e; e1])) (Ast.True def_loc) rhs_conjuncts
              in
              let post =
                Ast.Operation (def_loc, Eq, [
                  mk_send_expr def_loc structTypeExpr;
                  rhs
                ])
              in
              Ast.Func
                ( def_loc,
                  Lemma
                    ( true
                      (*indicates whether an axiom should be generated for this lemma*),
                      Some (mk_send_expr def_loc structTypeExpr)),
                  Ast.unbounded_tparams vf_tparams (*type parameters*),
                  None (*return type*),
                  qualified_derived_name "is_Send_%s_def" name,
                  [],
                  false (*nonghost_callers_only*),
                  (None, None)
                  (*implemented function type, with function type type arguments and function type arguments*),
                  Some (True def_loc, ("result", post)) (*contract*),
                  false (*terminates*),
                  Some
                    ( [
                        ExprStmt
                          (CallExpr
                            ( def_loc,
                              "#assume",
                              [],
                              [],
                              [ LitPat (False def_loc) ],
                              Static ));
                      ],
                      def_loc )
                  (*body*),
                  false (*virtual*),
                  [] (*overrides*) )
            ]
          in
          let sync_def_lemmas =
            if sync_impls <> [] then [] else
            [
              let rhs =
                let rhs_conjuncts =
                  fds |> List.map (fun fd -> mk_sync_expr def_loc fd.Mir.ty.Mir.vf_ty)
                in
                List.fold_left (fun e e1 -> Ast.Operation (def_loc, And, [e; e1])) (Ast.True def_loc) rhs_conjuncts
              in
              let post =
                Ast.Operation (def_loc, Eq, [
                  mk_sync_expr def_loc structTypeExpr;
                  rhs
                ])
              in
              Ast.Func
                ( def_loc,
                  Lemma
                    ( true
                      (*indicates whether an axiom should be generated for this lemma*),
                      Some (mk_sync_expr def_loc structTypeExpr)),
                  Ast.unbounded_tparams vf_tparams (*type parameters*),
                  None (*return type*),
                  qualified_derived_name "is_Sync_%s_def" name,
                  [],
                  false (*nonghost_callers_only*),
                  (None, None)
                  (*implemented function type, with function type type arguments and function type arguments*),
                  Some (True def_loc, ("result", post)) (*contract*),
                  false (*terminates*),
                  Some
                    ( [
                        ExprStmt
                          (CallExpr
                            ( def_loc,
                              "#assume",
                              [],
                              [],
                              [ LitPat (False def_loc) ],
                              Static ));
                      ],
                      def_loc )
                  (*body*),
                  false (*virtual*),
                  [] (*overrides*) )
            ]
          in
          let open_ref_init_perm_lemma =
            let pre =
              Ast.CallExpr
                ( def_loc,
                  "ref_init_perm",
                  [],
                  [],
                  [ LitPat (Var (def_loc, "p")); VarPat (def_loc, "x") ],
                  Static )
            in
            let post =
              let fd_ref_init_perm_asns =
                List.combine fds_no_zst field_types_no_zst
                |> Util.flatmap (fun (fd, fd_ty) ->
                       match fd_ty with
                       | `Adt ("std::cell::UnsafeCell", _, _) -> []
                       | _ ->
                           [
                             Ast.CallExpr
                               ( def_loc,
                                 "ref_init_perm",
                                 [],
                                 [],
                                 [
                                   LitPat
                                     (AddressOf
                                        ( def_loc,
                                          Select
                                            ( def_loc,
                                              Deref (def_loc, Var (def_loc, "p")),
                                              (fd : Mir.field_def_tr).name ) ));
                                   LitPat
                                     (AddressOf
                                        ( def_loc,
                                          Select
                                            ( def_loc,
                                              Deref (def_loc, Var (def_loc, "x")),
                                              (fd : Mir.field_def_tr).name ) ));
                                 ],
                                 Static );
                           ])
              in
              let ref_padding_init_perm_asn =
                match fds_no_zst with [_] -> Ast.EmpAsn def_loc | _ ->
                Ast.CallExpr
                  ( def_loc,
                    "ref_padding_init_perm",
                    [],
                    [],
                    [ LitPat (Var (def_loc, "p")); LitPat (Var (def_loc, "x")) ],
                    Static )
              in
              List.fold_right
                (fun a asn -> Ast.Sep (def_loc, a, asn))
                fd_ref_init_perm_asns ref_padding_init_perm_asn
            in
            Ast.Func
              ( def_loc,
                Lemma
                  ( false
                    (*indicates whether an axiom should be generated for this lemma*),
                    None (*trigger*) ),
                vf_tparams_with_bounds (*type parameters*),
                None (*return type*),
                qualified_derived_name "open_ref_init_perm_%s" name,
                [
                  ( PtrTypeExpr
                      ( def_loc,
                        StructTypeExpr
                          (def_loc, Some name, None, [], tparams_targs) ),
                    "p" );
                ],
                false (*nonghost_callers_only*),
                (None, None)
                (*implemented function type, with function type type arguments and function type arguments*),
                Some (pre, ("result", post)) (*contract*),
                false (*terminates*),
                Some
                  ( [
                      ExprStmt
                        (CallExpr
                           ( def_loc,
                             "#assume",
                             [],
                             [],
                             [ LitPat (False def_loc) ],
                             Static ));
                    ],
                    def_loc )
                (*body*),
                false (*virtual*),
                [] (*overrides*) )
          in
          let init_ref_padding_lemma =
            let ref_padding_init_perm_asn =
              Ast.CallExpr
                ( def_loc,
                  "ref_padding_init_perm",
                  [],
                  [],
                  [ LitPat (Var (def_loc, "p")); VarPat (def_loc, "x") ],
                  Static )
            in
            let padding_asn coefpat l =
              Ast.CoefAsn
                ( def_loc,
                  coefpat,
                  Ast.CallExpr
                    ( def_loc,
                      padding_pred_name name,
                      [],
                      [],
                      [ LitPat (Var (def_loc, l)) ],
                      Static ) )
            in
            let coef_limits =
              Ast.ExprAsn
                ( def_loc,
                  Operation
                    ( def_loc,
                      And,
                      [
                        Ast.Operation
                          ( def_loc,
                            Ast.Lt,
                            [
                              IntLit
                                ( def_loc,
                                  Big_int.zero_big_int,
                                  true,
                                  false,
                                  NoLSuffix );
                              Var (def_loc, "coef");
                            ] );
                        Ast.Operation
                          ( def_loc,
                            Ast.Lt,
                            [
                              Var (def_loc, "coef");
                              IntLit
                                ( def_loc,
                                  Big_int.unit_big_int,
                                  true,
                                  false,
                                  NoLSuffix );
                            ] );
                      ] ) )
            in
            let pre =
              Ast.Sep
                ( def_loc,
                  ref_padding_init_perm_asn,
                  Sep
                    ( def_loc,
                      padding_asn (VarPat (def_loc, "f")) "x",
                      coef_limits ) )
            in
            let one_minus_coef =
              Ast.Operation
                ( def_loc,
                  Sub,
                  [
                    IntLit
                      (def_loc, Big_int.unit_big_int, true, false, NoLSuffix);
                    Var (def_loc, "coef");
                  ] )
            in
            let f_times_one_minus_coef =
              Ast.Operation
                (def_loc, Mul, [ Var (def_loc, "f"); one_minus_coef ])
            in
            let f_times_coef =
              Ast.Operation
                (def_loc, Mul, [ Var (def_loc, "f"); Var (def_loc, "coef") ])
            in
            let ref_padding_initialized_asn =
              Ast.CallExpr
                ( def_loc,
                  "ref_padding_initialized",
                  [],
                  [],
                  [ LitPat (Var (def_loc, "p")) ],
                  Static )
            in
            let ref_padding_end_token_asn =
              Ast.CallExpr
                ( def_loc,
                  "ref_padding_end_token",
                  [],
                  [],
                  [
                    LitPat (Var (def_loc, "p"));
                    LitPat (Var (def_loc, "x"));
                    LitPat f_times_coef;
                  ],
                  Static )
            in
            let post =
              Ast.Sep
                ( def_loc,
                  padding_asn (LitPat f_times_one_minus_coef) "x",
                  Sep
                    ( def_loc,
                      padding_asn (LitPat f_times_coef) "p",
                      Sep
                        ( def_loc,
                          ref_padding_initialized_asn,
                          ref_padding_end_token_asn ) ) )
            in
            Ast.Func
              ( def_loc,
                Lemma
                  ( false
                    (*indicates whether an axiom should be generated for this lemma*),
                    None (*trigger*) ),
                vf_tparams_with_bounds (*type parameters*),
                None (*return type*),
                qualified_derived_name "init_ref_padding_%s" name,
                [
                  ( PtrTypeExpr
                      ( def_loc,
                        StructTypeExpr
                          (def_loc, Some name, None, [], tparams_targs) ),
                    "p" );
                  (ManifestTypeExpr (def_loc, RealType), "coef");
                ],
                false (*nonghost_callers_only*),
                (None, None)
                (*implemented function type, with function type type arguments and function type arguments*),
                Some (pre, ("result", post)) (*contract*),
                false (*terminates*),
                Some
                  ( [
                      ExprStmt
                        (CallExpr
                           ( def_loc,
                             "#assume",
                             [],
                             [],
                             [ LitPat (False def_loc) ],
                             Static ));
                    ],
                    def_loc )
                (*body*),
                false (*virtual*),
                [] (*overrides*) )
          in
          let end_ref_padding_lemma =
            let ref_padding_initialized_asn =
              Ast.CallExpr
                ( def_loc,
                  "ref_padding_initialized",
                  [],
                  [],
                  [ LitPat (Var (def_loc, "p")) ],
                  Static )
            in
            let ref_padding_end_token_asn =
              Ast.CallExpr
                ( def_loc,
                  "ref_padding_end_token",
                  [],
                  [],
                  [
                    LitPat (Var (def_loc, "p"));
                    VarPat (def_loc, "x");
                    VarPat (def_loc, "f");
                  ],
                  Static )
            in
            let padding_asn coefpat l =
              Ast.CoefAsn
                ( def_loc,
                  coefpat,
                  Ast.CallExpr
                    ( def_loc,
                      padding_pred_name name,
                      [],
                      [],
                      [ LitPat (Var (def_loc, l)) ],
                      Static ) )
            in
            let pre =
              Ast.Sep
                ( def_loc,
                  ref_padding_initialized_asn,
                  Sep
                    ( def_loc,
                      ref_padding_end_token_asn,
                      padding_asn (LitPat (Var (def_loc, "f"))) "p" ) )
            in
            let post = padding_asn (LitPat (Var (def_loc, "f"))) "x" in
            Ast.Func
              ( def_loc,
                Lemma
                  ( false
                    (*indicates whether an axiom should be generated for this lemma*),
                    None (*trigger*) ),
                vf_tparams_with_bounds (*type parameters*),
                None (*return type*),
                qualified_derived_name "end_ref_padding_%s" name,
                [
                  ( PtrTypeExpr
                      ( def_loc,
                        StructTypeExpr
                          (def_loc, Some name, None, [], tparams_targs) ),
                    "p" );
                ],
                false (*nonghost_callers_only*),
                (None, None)
                (*implemented function type, with function type type arguments and function type arguments*),
                Some (pre, ("result", post)) (*contract*),
                false (*terminates*),
                Some
                  ( [
                      ExprStmt
                        (CallExpr
                           ( def_loc,
                             "#assume",
                             [],
                             [],
                             [ LitPat (False def_loc) ],
                             Static ));
                    ],
                    def_loc )
                (*body*),
                false (*virtual*),
                [] (*overrides*) )
          in
          let close_ref_initialized_lemma =
            let pre =
              let ref_padding_initialized_asn =
                match fds_no_zst with [_] -> Ast.EmpAsn def_loc | _ ->
                Ast.CoefAsn
                  ( def_loc,
                    VarPat (def_loc, "f"),
                    CallExpr
                      ( def_loc,
                        "ref_padding_initialized",
                        [],
                        [],
                        [ LitPat (Var (def_loc, "p")) ],
                        Static ) )
              in
              let fd_ref_initialized_asns =
                List.combine fds_no_zst field_types_no_zst
                |> Util.flatmap (fun (fd, fd_ty) ->
                       match fd_ty with
                       | `Adt ("std::cell::UnsafeCell", _, _) -> []
                       | _ ->
                           [
                             Ast.CoefAsn
                               ( def_loc,
                                 LitPat (Var (def_loc, "f")),
                                 CallExpr
                                   ( def_loc,
                                     "ref_initialized",
                                     [],
                                     [],
                                     [
                                       LitPat
                                         (AddressOf
                                            ( def_loc,
                                              Select
                                                ( def_loc,
                                                  Deref
                                                    (def_loc, Var (def_loc, "p")),
                                                  (fd : Mir.field_def_tr).name
                                                ) ));
                                     ],
                                     Static ) );
                           ])
              in
              Ast.Sep
                ( def_loc,
                  ref_padding_initialized_asn,
                  List.fold_right
                    (fun a asn -> Ast.Sep (def_loc, a, asn))
                    fd_ref_initialized_asns (EmpAsn def_loc) )
            in
            let post =
              Ast.CoefAsn
                ( def_loc,
                  LitPat (Var (def_loc, "f")),
                  CallExpr
                    ( def_loc,
                      "ref_initialized",
                      [],
                      [],
                      [ LitPat (Var (def_loc, "p")) ],
                      Static ) )
            in
            let p_param =
              ( Ast.PtrTypeExpr
                  ( def_loc,
                    StructTypeExpr
                      (def_loc, Some name, None, [], tparams_targs) ),
                "p" )
            in
            let params = match fds_no_zst with [_] -> [p_param; Ast.ManifestTypeExpr (def_loc, RealType), "f"] | _ -> [p_param] in
            Ast.Func
              ( def_loc,
                Lemma
                  ( false
                    (*indicates whether an axiom should be generated for this lemma*),
                    None (*trigger*) ),
                vf_tparams_with_bounds (*type parameters*),
                None (*return type*),
                qualified_derived_name "close_ref_initialized_%s" name,
                params,
                false (*nonghost_callers_only*),
                (None, None)
                (*implemented function type, with function type type arguments and function type arguments*),
                Some (pre, ("result", post)) (*contract*),
                false (*terminates*),
                Some
                  ( [
                      ExprStmt
                        (CallExpr
                           ( def_loc,
                             "#assume",
                             [],
                             [],
                             [ LitPat (False def_loc) ],
                             Static ));
                    ],
                    def_loc )
                (*body*),
                false (*virtual*),
                [] (*overrides*) )
          in
          let open_ref_initialized_lemma =
            let pre =
              Ast.CoefAsn
                ( def_loc,
                  VarPat (def_loc, "f"),
                  CallExpr
                    ( def_loc,
                      "ref_initialized",
                      [],
                      [],
                      [ LitPat (Var (def_loc, "p")) ],
                      Static ) )
            in
            let post =
              let fd_ref_initialized_asns =
                List.combine fds_no_zst field_types_no_zst
                |> Util.flatmap (fun (fd, fd_ty) ->
                       match fd_ty with
                       | `Adt ("std::cell::UnsafeCell", _, _) -> []
                       | _ ->
                           [
                             Ast.CoefAsn
                               ( def_loc,
                                 LitPat (Var (def_loc, "f")),
                                 CallExpr
                                   ( def_loc,
                                     "ref_initialized",
                                     [],
                                     [],
                                     [
                                       LitPat
                                         (AddressOf
                                            ( def_loc,
                                              Select
                                                ( def_loc,
                                                  Deref
                                                    (def_loc, Var (def_loc, "p")),
                                                  (fd : Mir.field_def_tr).name
                                                ) ));
                                     ],
                                     Static ) );
                           ])
              in
              let ref_padding_initialized_asn =
                match fds_no_zst with [_] -> Ast.EmpAsn def_loc | _ ->
                Ast.CoefAsn
                  ( def_loc,
                    LitPat (Var (def_loc, "f")),
                    CallExpr
                      ( def_loc,
                        "ref_padding_initialized",
                        [],
                        [],
                        [ LitPat (Var (def_loc, "p")) ],
                        Static ) )
              in
              List.fold_right
                (fun a asn -> Ast.Sep (def_loc, a, asn))
                fd_ref_initialized_asns ref_padding_initialized_asn
            in
            Ast.Func
              ( def_loc,
                Lemma
                  ( false
                    (*indicates whether an axiom should be generated for this lemma*),
                    None (*trigger*) ),
                vf_tparams_with_bounds (*type parameters*),
                None (*return type*),
                qualified_derived_name "open_ref_initialized_%s" name,
                [
                  ( PtrTypeExpr
                      ( def_loc,
                        StructTypeExpr
                          (def_loc, Some name, None, [], tparams_targs) ),
                    "p" );
                ],
                false (*nonghost_callers_only*),
                (None, None)
                (*implemented function type, with function type type arguments and function type arguments*),
                Some (pre, ("result", post)) (*contract*),
                false (*terminates*),
                Some
                  ( [
                      ExprStmt
                        (CallExpr
                           ( def_loc,
                             "#assume",
                             [],
                             [],
                             [ LitPat (False def_loc) ],
                             Static ));
                    ],
                    def_loc )
                (*body*),
                false (*virtual*),
                [] (*overrides*) )
          in
          Ok
            ( Some full_bor_content,
              own_proof_obligs @ share_proof_obligs,
              delayed_proof_obligs,
              upcast_lemmas
              @ send_lemmas @ send_def_lemmas @ sync_lemmas @ sync_def_lemmas @ open_ref_init_perm_lemma :: init_ref_padding_lemma
                :: close_ref_initialized_lemma :: open_ref_initialized_lemma
                :: end_ref_padding_lemma :: type_pred_defs ))
        else Ok (None, [], [], [])
      in
      Ok
        (Some
           Mir.
             {
               loc = def_loc;
               name;
               tparams;
               lft_params;
               fds_no_zst;
               def;
               aux_decls = aux_decls @ aux_decls';
               full_bor_content;
               proof_obligs;
               delayed_proof_obligs;
             })

  (** Checks for the existence of a lemma for proof obligation in ghost code.
      The consistency of the lemma with proof obligation will be checked by VeriFast later *)
  let check_proof_obligations gh_decl_map proof_obligs =
    let unmet_proof_obligs =
      proof_obligs
      |> List.filter @@ fun po ->
         let (Some po_name) = AstAux.decl_name po in
         match Util.try_assoc po_name gh_decl_map with
         | Some (Ast.Func (_, _, _, _, _, _, _, _, _, _, Some body, _, _)) ->
             false
         | _ -> true
    in
    if unmet_proof_obligs <> [] then
      let loc = AstAux.decl_loc (List.hd unmet_proof_obligs) in
      let unmet_proof_obligs_at_loc =
        List.filter (fun po -> AstAux.decl_loc po = loc) unmet_proof_obligs
      in
      let msg, descr =
        match unmet_proof_obligs_at_loc with
        | [ po ] ->
            ( Printf.sprintf "Lemma %s should be proven"
                (Option.get (AstAux.decl_name po)),
              "Insert lemma template" )
        | pos ->
            ( Printf.sprintf "Lemmas %s should be proven"
                (String.concat ", "
                   (List.map (fun po -> Option.get (AstAux.decl_name po)) pos)),
              "Insert lemma templates" )
      in
      let (Lexed (_, end_pos)) = loc in
      let text_to_insert =
        Printf.sprintf "\n\n/*@\n\n%s\n\n@*/"
        @@ String.concat "\n\n"
        @@ List.map Ast_to_src.string_of_decl unmet_proof_obligs_at_loc
      in
      raise
        (Ast.StaticError
           ( loc,
             msg,
             Some
               [
                 HelpTopic "rust-struct-proof-obligations";
                 QuickFix (descr, InsertTextAt (end_pos, text_to_insert));
               ] ))
    else Ok ()

  let translate_trait_impls (trait_impls_cpn : TraitImplRd.t list) =
    trait_impls_cpn
    |> ListAux.try_map (fun trait_impl_cpn ->
           let open TraitImplRd in
           let* loc = translate_span_data (span_get trait_impl_cpn) in
           let is_unsafe = is_unsafe_get trait_impl_cpn in
           let is_negative = is_negative_get trait_impl_cpn in
           let of_trait = of_trait_get trait_impl_cpn in
           let gen_args =
             List.map Vf_mir_decoder.decode_generic_arg
             @@ gen_args_get_list trait_impl_cpn
           in
           let self_ty = self_ty_get trait_impl_cpn in
           let generics =
             List.map Vf_mir_decoder.decode_generic_param_def
             @@ generics_get_list trait_impl_cpn
           in
           let clauses =
             List.map Vf_mir_decoder.decode_clause
             @@ clauses_get_list trait_impl_cpn
           in
           let items =
             items_get_list trait_impl_cpn |> List.map D.decode_trait_impl_item
           in
           Ok
             ({
                trait_impl_cpn;
                loc;
                is_unsafe;
                is_negative;
                of_trait;
                gen_args;
                self_ty;
                generics;
                clauses;
                items;
              }
               : trait_impl))

  let ( >>= ) = Option.bind

  type match_env = {
    type_env : (string * Vf_mir_decoder.ty) list;
    lifetime_env : (string * string) list;
    const_env : (string * Vf_mir_decoder.ty_const) list;
  }

  let empty_match_env = { type_env = []; lifetime_env = []; const_env = [] }

  (* Returns an extension of env such that arg1[env] = arg2, or None if none exists. *)
  let rec match_gen_args env (arg1 : Vf_mir_decoder.generic_arg)
      (arg2 : Vf_mir_decoder.generic_arg) =
    match (arg1.kind, arg2.kind) with
    | Lifetime { id = "'static'" }, Lifetime { id = "'static'" } -> Some env
    | Lifetime { id = id1 }, Lifetime { id = id2 } ->
        begin match List.assoc_opt id1 env.lifetime_env with
        | None -> Some { env with lifetime_env = (id1, id2) :: env.lifetime_env }
        | Some id1' -> if id1' = id2 then Some env else None
        end
    | Type ty1, Type ty2 -> match_types env ty1 ty2
    | Const c1, Const c2 -> None (* TODO *)

  and match_gen_arg_lists env args1 args2 =
    match (args1, args2) with
    | [], [] -> Some env
    | arg1 :: rest1, arg2 :: rest2 ->
        match_gen_args env arg1 arg2 >>= fun env' ->
        match_gen_arg_lists env' rest1 rest2
    | _ -> None

  and match_types env ty1 ty2 =
    match (ty1.kind, ty2.kind) with
    | Param x, _ -> (
        match List.assoc_opt x env.type_env with
        | None -> Some { env with type_env = (x, ty2) :: env.type_env }
        | Some ty1' -> match_types env ty1' ty2)
    | Bool, Bool -> Some env
    | Never, Never -> Some env
    | Int intTy1, Int intTy2 -> if intTy1 = intTy2 then Some env else None
    | UInt uintTy1, UInt uintTy2 -> if uintTy1 = uintTy2 then Some env else None
    | Adt { id = id1; substs = substs1 }, Adt { id = id2; substs = substs2 } ->
        if canonicalize_item_name id1.name = canonicalize_item_name id2.name then match_gen_arg_lists env substs1 substs2 else None
    | ( RawPtr { ty = ty1; mutability = mut1 },
        RawPtr { ty = ty2; mutability = mut2 } ) ->
        if mut1 = mut2 then match_types env ty1 ty2 else None
    | _ -> None

  and match_type_lists env tys1 tys2 =
    match (tys1, tys2) with
    | [], [] -> Some env
    | ty1 :: rest1, ty2 :: rest2 ->
        match_types env ty1 ty2 >>= fun env' ->
        match_type_lists env' rest1 rest2
    | _ -> None

  let compute_trait_impl_fn_specialisations trait_impls =
    trait_impls
    |> Util.flatmap
         (fun { of_trait; gen_args; self_ty; generics; clauses; items } ->
           items
           |> List.map
                (fun
                  ({ name = item_name; def_id = item_def_id } :
                    D.trait_impl_item)
                ->
                  let trait_fn_name =
                    Printf.sprintf "%s::%s" of_trait item_name
                  in
                  let specializer substs =
                    let trait_substs, fn_substs =
                      Util.take_drop (List.length gen_args) substs
                    in
                    match
                      match_gen_arg_lists empty_match_env gen_args trait_substs
                    with
                    | None -> None
                    | Some env ->
                        let substs' : Vf_mir_decoder.generic_arg list =
                          generics
                          |> List.map
                               (fun
                                 ({ name; kind } :
                                   Vf_mir_decoder.generic_param_def)
                                 :
                                 Vf_mir_decoder.generic_arg
                               ->
                                 match kind with
                                 | Lifetime ->
                                     {
                                       kind =
                                         Lifetime
                                           {
                                             id =
                                               List.assoc name env.lifetime_env;
                                             identity = Nothing;
                                           };
                                     }
                                 | Type ->
                                     {
                                       kind =
                                         Type (List.assoc name env.type_env);
                                     }
                                 | Const ->
                                     {
                                       kind =
                                         Const (List.assoc name env.const_env);
                                     })
                        in
                        clauses
                        |> List.iter (fun clause ->
                               Printf.printf
                                 "WARNING: fn_specializer: rerouting call of %s to %s: ignoring clause %s\n"
                                 trait_fn_name item_def_id (string_of_clause @@ decode_clause clause));
                        Some (item_def_id, substs' @ fn_substs)
                  in
                  (canonicalize_item_name trait_fn_name, specializer)))

  let compute_trait_impl_prototypes (adt_defs : Mir.adt_def_tr list)
      traits_and_body_decls trait_impls =
    trait_impls
    |> Util.flatmap (fun { loc = limpl; of_trait; self_ty; items } ->
           let items =
             List.map (fun ({ name } : D.trait_impl_item) -> name) items
           in
           if of_trait = "std::ops::Drop" then (
             assert (items = [ "drop" ]);
             [] (* drop is safe *))
           else if of_trait = "std::ops::Deref" then (
             assert (items = [ "Target"; "deref" ]);
             [] (* Deref is safe *))
           else if of_trait = "std::ops::DerefMut" then (
             assert (items = [ "deref_mut" ]);
             [] (* DerefMut is safe *))
           else if of_trait = "std::clone::Clone" then []
             (* clone is safe *)
             (* TODO: Support for traits from other crates. I think it is generally sound to ignore safe traits here *)
           else
             items
             |> Util.flatmap (fun item ->
                    let trait_fn_name = Printf.sprintf "%s::%s" of_trait item in
                    let impl_fn_name =
                      Printf.sprintf "<%s as %s>::%s" self_ty of_trait item
                    in
                    match
                      traits_and_body_decls
                      |> Util.head_flatmap_option (function
                           | Ast.Func
                               ( lf,
                                 Regular,
                                 ("Self", _) :: tparams,
                                 rt,
                                 name,
                                 ps,
                                 false,
                                 (None, None),
                                 Some (pre, (result_var, post)),
                                 terminates,
                                 body,
                                 false,
                                 [] )
                             when name = trait_fn_name ->
                               let self_ty_typeid =
                                 Ast.Typeid
                                   ( lf,
                                     Ast.TypeExpr
                                       (Ast.ManifestTypeExpr
                                          (lf, Ast.StructType (self_ty, []))) )
                               in
                               let pre =
                                 Ast.LetTypeAsn
                                   ( lf,
                                     "Self",
                                     Ast.StructType (self_ty, []),
                                     Ast.Sep
                                       ( lf,
                                         MatchAsn
                                           ( lf,
                                             self_ty_typeid,
                                             VarPat (lf, "Self_typeid") ),
                                         Ast.Sep
                                           ( lf,
                                             pre,
                                             Ast.EnsuresAsn
                                               (lf, result_var, post) ) ) )
                               in
                               let post = Ast.EmpAsn lf in
                               Some
                                 (Ast.Func
                                    ( lf,
                                      Regular,
                                      tparams,
                                      rt,
                                      impl_fn_name,
                                      ps,
                                      false,
                                      (None, None),
                                      Some (pre, ("result", post)),
                                      terminates,
                                      None,
                                      false,
                                      [] ))
                           | _ -> None)
                    with
                    | Some prototype -> [ prototype ]
                    | None -> []))

  let rec translate_module (module_cpn : VfMirRd.Module.t) :
      (Ast.decl, _) result =
    let open VfMirRd.Module in
    let name = name_get module_cpn in
    let* loc = translate_span_data (header_span_get module_cpn) in
    let* submodules =
      submodules_get_list module_cpn |> ListAux.try_map translate_module
    in
    let* ghost_decl_batches =
      ListAux.try_map translate_ghost_decl_batch
        (ghost_decl_batches_get_list module_cpn)
    in
    let imports, decls = List.partition_map (fun x -> x) ghost_decl_batches in
    let decls = List.flatten decls in
    let decls =
      if Args.ignore_unwind_paths then
        List.map Rust_parser.result_decl_of_outcome_decl decls
      else decls
    in
    Ok (Ast.ModuleDecl (loc, name, List.flatten imports, submodules @ decls))

  let modularize_decl module_imports_map (d : Ast.decl) : Ast.decl =
    match AstAux.decl_loc_name_and_name_setter d with
    | None -> d
    | Some (l, name, name_setter) ->
        if String.contains name ':' then
          let segments = String.split_on_char ':' name in
          let rec iter segs = function
            | segment :: "" :: segments ->
                let segs = segment :: segs in
                let imports =
                  match segments with
                  | [ _ ] -> (
                      let moduleName = String.concat "::" (List.rev segs) in
                      match List.assoc_opt moduleName module_imports_map with
                      | None -> []
                      | Some imports -> imports)
                  | _ -> []
                in
                Ast.ModuleDecl (l, segment, imports, [ iter segs segments ])
            | [ segment ] -> name_setter segment
            | _ ->
                failwith
                  (Printf.sprintf "Unexpected shape of Rust item name: '%s'"
                     name)
          in
          iter [] segments
        else d

  let modularize_fn_decl module_imports_map
      (((moduleName : string), (fnName : string)), (d : Ast.decl)) : Ast.decl =
    let (Some (l, name, name_setter)) =
      AstAux.decl_loc_name_and_name_setter d
    in
    if moduleName <> "" then
      let imports =
        match List.assoc_opt moduleName module_imports_map with
        | None -> []
        | Some imports -> imports
      in
      let d = name_setter fnName in
      let segments = String.split_on_char ':' moduleName in
      let rec iter = function
        | segment :: "" :: segments ->
            Ast.ModuleDecl (l, segment, [], [ iter segments ])
        | [ segment ] -> Ast.ModuleDecl (l, segment, imports, [ d ])
        | _ ->
            failwith
              (Printf.sprintf "Unexpected shape of Rust module name: '%s'"
                 moduleName)
      in
      iter segments
    else d

  let package_extract_fn_specialization_decls (Ast.PackageDecl (l, pn, ilist, ds)) =
    let ds, fn_specialization_decls =
      ds |> List.partition_map @@ fun d ->
          match d with
          | Ast.FuncSpecializationDecl (l, g_generic, g_generic_is_relative, g_specialized, tparams, targs) -> Right (l, (if not g_generic_is_relative || pn = "" then "" else pn ^ "::") ^ g_generic, (if pn = "" then "" else pn ^ "::") ^ g_specialized, tparams, targs)
          | _ -> Left d
    in
    Ast.PackageDecl (l, pn, ilist, ds), fn_specialization_decls

  (* Extracts fn_specialization_decls from a header and returns them separately *)
  let header_extract_fn_specialization_decls (l, incl, hs, ps) =
    let ps, fn_specialization_decls = List.split @@ List.map package_extract_fn_specialization_decls ps in
    (l, incl, hs, ps), List.flatten fn_specialization_decls

  let rec generic_arg_of_type_expr tparams: Ast.type_expr -> D.generic_arg = function
    (* `std::convert::Infallible` is a type alias for `!` *)
    | Ast.IdentTypeExpr (_, None, "std::convert::Infallible")
    | Ast.ManifestTypeExpr (_, UnionType "std_empty_") -> { kind = Type {kind=Never} }
    | Ast.IdentTypeExpr (_, None, x) ->
      if List.mem_assoc x tparams then
        if String.starts_with ~prefix:"'" x then
          { kind = Lifetime { id = x; identity = Nothing } }
        else
          { kind = Type {kind=Param x} }
      else
        { kind = Type {kind=Adt { id = {name=x}; kind=StructKind; substs = [] }} }
    | Ast.ConstructedTypeExpr (_, x, targs) ->
      { kind = Type {kind=Adt { id = {name=x}; kind=StructKind; substs = List.map (generic_arg_of_type_expr tparams) targs }} }
    | Ast.ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 0)) -> {kind = Type {kind=UInt U8}}
    | Ast.ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 1)) -> {kind = Type {kind=UInt U16}}
    | Ast.ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 2)) -> {kind = Type {kind=UInt U32}}
    | Ast.ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 3)) -> {kind = Type {kind=UInt U64}}
    | Ast.ManifestTypeExpr (_, Int (Unsigned, FixedWidthRank 4)) -> {kind = Type {kind=UInt U128}}
    | Ast.ManifestTypeExpr (_, Int (Unsigned, PtrRank)) -> {kind = Type {kind=UInt USize}}
    | Ast.ManifestTypeExpr (_, Int (Signed, FixedWidthRank 0)) -> {kind = Type {kind=Int I8}}
    | Ast.ManifestTypeExpr (_, Int (Signed, FixedWidthRank 1)) -> {kind = Type {kind=Int I16}}
    | Ast.ManifestTypeExpr (_, Int (Signed, FixedWidthRank 2)) -> {kind = Type {kind=Int I32}}
    | Ast.ManifestTypeExpr (_, Int (Signed, FixedWidthRank 3)) -> {kind = Type {kind=Int I64}}
    | Ast.ManifestTypeExpr (_, Int (Signed, FixedWidthRank 4)) -> {kind = Type {kind=Int I128}}
    | Ast.ManifestTypeExpr (_, Int (Signed, PtrRank)) -> {kind = Type {kind=Int ISize}}
    | te -> Ast.static_error (Ast.type_expr_loc te) "This type expression is not supported in function specializations" None

  let translate_vf_mir (extern_specs : string list)
      (vf_mir_cpn : VfMirRd.VfMir.t) =
    let job _ =
      Rocq_writer.rocq_print Args.rocq_writer "From VeriFast Require Export VfMir.\n\n";
      (* Todo @Nima: we should add necessary inclusions during translation *)
      let extern_header_names =
        extern_specs
        |> List.map @@ fun extern_spec ->
           match String.split_on_char '=' extern_spec with
           | [ crateName; header_path ] -> (crateName, header_path)
           | _ ->
               failwith
                 (Printf.sprintf
                    "-extern_spec argument '%s' should be of the form \
                     `crateName=path/to/spec_file.rsspec`"
                    extern_spec)
      in
      let header_names =
        [
          ( "std",
            Filename.concat
              (Filename.dirname Sys.executable_name)
              "rust/std/lib.rsspec" );
        ]
        @ extern_header_names
      in
      let headers =
        parse_prelude ()
        @ Util.flatmap
            (fun (crateName, header_path) -> parse_header crateName header_path)
            header_names
      in
      let headers =
        if TranslatorArgs.ignore_unwind_paths then
          List.map Rust_parser.result_header_of_outcome_header headers
        else headers
      in
      let headers, fn_specialization_decls =
        List.split (List.map header_extract_fn_specialization_decls headers)
      in
      let fn_specialization_decls = List.flatten fn_specialization_decls in
      let fn_specializations = fn_specialization_decls |> List.map @@ fun (l, g_generic, g_specialized, tparams, targs) ->
        let targs = List.map (generic_arg_of_type_expr tparams) targs in
        let specialize substs =
          let string_of_generic_arg t = string_of_generic_arg (decode_generic_arg t) in
          match match_gen_arg_lists empty_match_env targs substs with
          | None ->
            if List.mem "specializer" Args.verbose_flags then
              Printf.printf "INFO: Function specialization resolver: did not specialize call of %s::<%s> to %s::<%s>: generic arguments do not match <%s>\n" g_generic (String.concat ", " (List.map string_of_generic_arg substs)) g_specialized (String.concat ", " (List.map fst tparams)) (String.concat ", " (List.map string_of_generic_arg targs));
            None
          | Some env ->
              let substs' : Vf_mir_decoder.generic_arg list =
                tparams
                |> List.map @@ fun (x, _): D.generic_arg ->
                    if String.starts_with ~prefix:"'" x then
                      { kind = Lifetime { id = List.assoc x env.lifetime_env; identity = Nothing } }
                    else
                      { kind = Type (List.assoc x env.type_env) }
              in
              Some (g_specialized, substs')
        in
        g_generic, specialize
      in
      let directives_cpn = VfMirRd.VfMir.directives_get_list vf_mir_cpn in
      let* directives = ListAux.try_map translate_annotation directives_cpn in
      let vf_mir_translator_directives, vf_directives =
        directives
        |> List.partition (fun { Mir.raw } -> raw = "ignore_ref_creation")
      in
      vf_directives
      |> List.iter (fun ({ span; raw } : Mir.annot) ->
             Args.report_should_fail raw (Ast.lexed_loc span));
      let* module_decls =
        ListAux.try_map translate_module
          (VfMirRd.VfMir.modules_get_list vf_mir_cpn)
      in
      let module_imports_map =
        let rec iter moduleName module_decls =
          List.concat_map
            (function
              | Ast.ModuleDecl (_, name, imports, submodules) ->
                  let name =
                    if moduleName = "" then name else moduleName ^ "::" ^ name
                  in
                  (name, imports) :: iter name submodules
              | _ -> [])
            module_decls
        in
        iter "" module_decls
      in
      let ghost_decl_batches_cpn =
        VfMirRd.VfMir.ghost_decl_batches_get_list vf_mir_cpn
      in
      let* ghost_decl_batches =
        ListAux.try_map translate_ghost_decl_batch ghost_decl_batches_cpn
      in
      let ghost_imports, ghost_decl_batches =
        List.partition_map (fun x -> x) ghost_decl_batches
      in
      let ghost_decl_batches = List.flatten ghost_decl_batches in
      let ghost_decl_batches =
        if Args.ignore_unwind_paths then
          List.map Rust_parser.result_decl_of_outcome_decl ghost_decl_batches
        else ghost_decl_batches
      in
      let ghost_decls = module_decls @ ghost_decl_batches in
      let ghost_decl_map = AstAux.decl_map_of ghost_decls in
      let* trait_impls =
        translate_trait_impls (VfMirRd.VfMir.trait_impls_get_list vf_mir_cpn)
      in
      let fn_specialisations =
        compute_trait_impl_fn_specialisations trait_impls @
        fn_specializations
      in
      let fn_specialisations_table = Hashtbl.create 10 in
      Hashtbl.add_seq fn_specialisations_table (List.to_seq fn_specialisations);
      let fn_specializer trait_fn substs =
        let trait_fn = canonicalize_item_name trait_fn in
        let rec iter = function
          [] -> (trait_fn, substs)
        | f::fs ->
          match f substs with
            None -> iter fs
          | Some result -> result
        in
        iter (Hashtbl.find_all fn_specialisations_table trait_fn)
      in
      let target_triple = VfMirRd.VfMir.target_triple_get vf_mir_cpn in
      let pointer_width = VfMirRd.VfMir.pointer_width_get vf_mir_cpn in
      let adt_defs_cpn = VfMirRd.VfMir.adt_defs_get vf_mir_cpn in
      let* adt_defs_cpn = CapnpAux.ind_list_get_list adt_defs_cpn in
      let* adt_defs =
        ListAux.try_map
          (translate_adt_def target_triple pointer_width ghost_decl_map ghost_decls trait_impls)
          adt_defs_cpn
      in
      let adt_defs = List.filter_map Fun.id adt_defs in
      (* Todo @Nima: External definitions and their corresponding ghost headers inclusion should be handled in a better way *)
      (* Todo @Nima: The MIR exporter encodes `ADT`s and adds the `ADT` declarations used in them later in the same array.
         For a Tree hierarchy of types just reversing the array works but obviously
         for more complicated scenarios we need to add all of the declarations without definitions first
         and then add all of the complete declarations
         Note that the following `fold_left` also reverses the list
      *)
      let adt_decls, aux_decls, adts_full_bor_content_preds, adts_proof_obligs =
        List.fold_left
          (fun (defs, ads, fbors, pos)
               Mir.{ def; aux_decls; full_bor_content; proof_obligs } ->
            ( def :: defs,
              aux_decls @ ads,
              full_bor_content :: fbors,
              proof_obligs @ pos ))
          ([], [], [], []) adt_defs
      in
      let adts_proof_obligs =
        Util.flatmap
          (fun (adt_def : Mir.adt_def_tr) ->
            List.map (fun ob -> ob adt_defs) adt_def.delayed_proof_obligs)
          adt_defs
        @ adts_proof_obligs
      in
      let adts_full_bor_content_preds =
        List.filter_map Fun.id adts_full_bor_content_preds
      in
      let* _ = check_proof_obligations ghost_decl_map adts_proof_obligs in
      let* ty_alias_decls = ListAux.try_map translate_ty_alias_decl (VfMirRd.VfMir.ty_aliases_get_list vf_mir_cpn) in
      let* traits_cpn =
        CapnpAux.ind_list_get_list (VfMirRd.VfMir.traits_get vf_mir_cpn)
      in
      let* traits_decls =
        ListAux.try_map
          (translate_trait adt_defs Args.skip_specless_fns)
          traits_cpn
      in
      let traits_decls = List.flatten traits_decls in
      let bodies_cpn = VfMirRd.VfMir.bodies_get_list vf_mir_cpn in
      List.iter (fun body ->
        if VfMirRd.GeneratedGlue.enabled_get (BodyRd.generated_glue_get body) &&
           BodyRd.DefKind.get (BodyRd.def_kind_get body) <> BodyRd.DefKind.Fn then
          Ast.static_error Ast.DummyLoc
            "Tagged generated Drop glue must be a function body" None)
        bodies_cpn;
      let bodies_cpn =
        bodies_cpn
        |> List.filter (fun body_cpn ->
               BodyRd.DefKind.get (BodyRd.def_kind_get body_cpn)
               <> BodyRd.DefKind.Closure)
      in
      (* It's okay to ignore closure bodies so long as we crash when we encounter closure types as function call generic arguments. *)
      let bodies_cpn =
        if Args.skip_specless_fns then
          List.filter
            (fun body_cpn ->
              VfMirRd.GeneratedGlue.enabled_get (BodyRd.generated_glue_get body_cpn) ||
              not
                (Capnp.Array.is_empty
                   (ContractRd.annotations_get (BodyRd.contract_get body_cpn))))
            bodies_cpn
        else bodies_cpn
      in
      let selected_drops = List.filter_map (fun body ->
        if not (BodyRd.is_drop_fn_get body) ||
           BodyRd.generics_get_list body <> [] ||
           BodyRd.impl_block_generics_get_list body <> [] ||
           Capnp.Array.is_empty (ContractRd.annotations_get (BodyRd.contract_get body)) then None
        else match BodyRd.inputs_get_list body with
        | [input] -> begin match decode_ty (D.decode_ty input) with
          | `Ref (_, _, `Adt (id, _, [])) ->
              let guard = id in
              begin match concrete_drop_effect_decl ghost_decl_map adt_defs guard [] [] with
              | None -> None
              | Some _ -> Some (TrName.translate_def_path (BodyRd.def_path_get body),
                                BodyRd.def_path_hash_get body, guard)
              end
          | _ -> None
          end
        | _ -> None) bodies_cpn in
      let* generated_glue =
        let generated_bodies = List.filter (fun body ->
          VfMirRd.GeneratedGlue.enabled_get (BodyRd.generated_glue_get body))
          bodies_cpn in
        match generated_bodies with
        | [] -> Ok None
        | [generated_body] ->
            let descriptor = BodyRd.generated_glue_get generated_body in
            let module G = VfMirRd.GeneratedGlue in
            let* loc = translate_span_data (BodyRd.span_get generated_body) in
            let fail reason = Ast.static_error loc reason None in
            let key = G.body_key_get descriptor in
            if List.length (List.filter (fun body ->
              TrName.translate_def_path (BodyRd.def_path_get body) = key)
              bodies_cpn) <> 1 then
              fail "Generated Drop glue key is missing or duplicated";
            let guard = TrName.translate_def_path (G.guard_path_get descriptor) in
            let selected_path = TrName.translate_def_path (G.selected_drop_path_get descriptor) in
            let selected_hash = G.selected_drop_hash_get descriptor in
            let resolved_args = G.resolved_args_get_list descriptor in
            let instance_args = G.instance_args_get_list descriptor in
            let concrete_arg = match instance_args with
              | [arg] ->
                  (match (D.decode_generic_arg arg).kind with
                   | Type ty ->
                       (match decode_ty ty with
                        | `Adt (name, _, []) -> Some name
                        | _ -> None)
                   | _ -> None)
              | _ -> None in
            if key <> "__vf_generated_drop_glue" ||
               TrName.translate_def_path (BodyRd.def_path_get generated_body) <> key ||
               G.instance_kind_get descriptor <> "DropGlue" ||
               G.glue_def_path_get descriptor = "" ||
               G.glue_def_hash_get descriptor = "" ||
               G.guard_hash_get descriptor = "" ||
               selected_hash = "" ||
               G.selected_source_hash_get descriptor = "" ||
               canonicalize_item_name (G.raw_trait_path_get descriptor)
                 <> "std::ops::Drop::drop" ||
               G.raw_trait_hash_get descriptor = "" ||
               G.raw_trait_args_get descriptor = "" ||
               G.unwind_kind_get descriptor <> "Continue" ||
               G.mir_phase_get descriptor <> "Runtime(Optimized)" ||
               BodyRd.captured_mir_phase_get generated_body <> "Runtime(Optimized)" ||
               BodyRd.captured_mir_hash_get generated_body = "" ||
               G.selected_source_phase_get descriptor <> "Runtime(PostCleanup)" ||
               Stdint.Uint32.to_string (G.normal_target_get descriptor) <> "1" ||
               concrete_arg <> Some guard || resolved_args <> [] ||
               not (List.mem (selected_path, selected_hash, guard) selected_drops) then
              fail "Generated Drop glue descriptor is outside the admitted concrete instance";
            let method_bodies = List.filter (fun body ->
              BodyRd.is_drop_fn_get body &&
              TrName.translate_def_path (BodyRd.def_path_get body) = selected_path &&
              BodyRd.def_path_hash_get body = selected_hash &&
              BodyRd.captured_mir_hash_get body = G.selected_source_hash_get descriptor &&
              BodyRd.captured_mir_phase_get body = G.selected_source_phase_get descriptor)
              bodies_cpn in
            let method_body = match method_bodies with
              | [method_body] -> method_body
              | _ -> fail "Generated Drop glue needs exactly one matching checked source method" in
            (match BodyRd.inputs_get_list method_body with
             | [input] ->
                 (match decode_ty (D.decode_ty input) with
                  | `Ref (_, true, `Adt (name, _, [])) when name = guard -> ()
                  | _ -> fail "Selected Drop method receiver is not the concrete mutable guard")
             | _ -> fail "Selected Drop method receiver arity changed");
            Ok (Some { glue_key = key; glue_guard = guard;
                   glue_selected_path = selected_path;
                   glue_selected_hash = selected_hash;
                   glue_raw_trait_path = G.raw_trait_path_get descriptor;
                   glue_raw_trait_hash = G.raw_trait_hash_get descriptor;
                   glue_method_body = method_body })
        | _ -> Ast.static_error Ast.DummyLoc
            "Multiple generated Drop glue bodies in one exported unit" None
      in
      let body_tr_defs_ctx =
        let r23_checked_slice_helpers = List.filter (fun body ->
          let name = TrName.translate_def_path (BodyRd.def_path_get body) in
          name = "r23_checked_slice_as_mut_ptr" ||
          String.ends_with ~suffix:"::r23_checked_slice_as_mut_ptr" name)
          bodies_cpn in
        let r23_checked_slice_helper = match r23_checked_slice_helpers with
          | [helper] -> Some helper
          | _ -> None in
        { selected_drops; generated_glue; adt_defs; ghost_decl_map;
          directives = vf_mir_translator_directives; fn_specializer;
          r23_checked_slice_helper }
      in
      let* bodies_tr_res =
        Rocq_writer.rocq_print Args.rocq_writer "Definition bodies := ";
        Rocq_writer.rocq_print_big_list Args.rocq_writer @@ fun () ->
        bodies_cpn |> ListAux.try_map @@ fun body_cpn ->
          Rocq_writer.rocq_print_big_list_element Args.rocq_writer @@ fun () ->
          translate_body body_tr_defs_ctx body_cpn
      in
      Rocq_writer.rocq_print Args.rocq_writer ".\n";
      let body_sig_opts, body_decls, debug_infos =
        ListAux.split3 bodies_tr_res
      in
      let body_sigs = List.filter_map Fun.id body_sig_opts in
      (* `vfide` relies on the similarity of the order of function declarations
         over several calls to `verifast` hence we are sorting them since `rustc` does not keep that order the same.
      *)
      let body_sigs = AstAux.sort_decls_lexically body_sigs in
      let body_decls = AstAux.sort_decls_lexically body_decls in
      let traits_and_body_decls = traits_decls @ List.map snd body_decls in
      let debug_infos = VF0.DbgInfoRustFe debug_infos in
      let trait_impl_prototypes =
        compute_trait_impl_prototypes adt_defs traits_and_body_decls trait_impls
      in
      (* Hack: for structs, functions, and other item-likes inside modules we
         currently generate toplevel VF declarations with paths as names. However, to properly resolve names inside those declarations,
         they need to be inside appropriate `ModuleDecl`s. `modularize_decl` does this. TODO: Generate the declarations inside the right
         module declarations from the start. This will become necessary once we want to take real `use` items into account inside annotations.*)
      let decls =
        List.map
          (modularize_decl module_imports_map)
          (ty_alias_decls @ traits_decls @ trait_impl_prototypes @ adt_decls @ aux_decls
         @ adts_full_bor_content_preds @ adts_proof_obligs)
        @ ghost_decls
        @ List.map
            (modularize_fn_decl module_imports_map)
            (body_sigs @ body_decls)
      in
      Ok
        ( headers,
          Rust_parser.flatten_module_decls Ast.dummy_loc
            (List.flatten ghost_imports)
            decls,
          Some debug_infos )
    in
    match job () with
    | Ok res -> res
    | Error err -> (
        match err with
        | `AdtTyName str
        | `CapnpIndListGetList str
        | `ChekProofObligationFatal str
        | `DeclMirAdtKind str
        | `GenAdtFullBorContent str
        | `GenAdtProofObligs str
        | `GenLocalTyAsn str
        | `GetAdtDef str
        | `GetLastColLoc str
        | `IntAuxAdd str
        | `IsWellFormedLoc0 str
        | `IsWellFormedSrcPos str
        | `LftNameWithoutApostrophe str
        | `SizeAuxSzBitsOfInt str
        | `Sort str
        | `TrAdtDef str
        | `TrAdtTy str
        | `TrAggregate str
        | `TrAggregateKind str
        | `TrBinOp str
        | `TrBodyFatal str
        | `TrConstValue str
        | `TrConstantKind str
        | `TrContract str
        | `TrFileName str
        | `TrFnCall str
        | `TrFnCallRExpr str
        | `TrFnDefTy str
        | `TrGenArg str
        | `TrHirGenericParamKind str
        | `TrHirGenericParamName str
        | `TrMutability str
        | `TrOperand str
        | `TrPlaceElement str
        | `TrRealFileName str
        | `TrRvalue str
        | `TrScalar str
        | `TrScalarUint str
        | `TrStatementKind str
        | `TrSwInt str
        | `TrTerminatorKind str
        | `TrToVfBBlock str
        | `TrTy str
        | `TrTyConstKind str
        | `TrUIntTy str
        | `TrUnsafety str
        | `TrVarDebugInfoContents str
        | `TrVisibility str
        | `TryCompareLoc str
        | `TryCompareSrcPos str
        | `UIntTyBitsLen str ->
            print_endline ("MIR Translator Failed: " ^ str);
            raise (Parser.CompilationError "Rust Translator Error")
        | `IntAuxToInt ->
            raise
              (Parser.CompilationError "Rust Translator Error: to int failed")
        | `CheckProofObligationFailed (loc, str) | `TrBodyFailed (loc, str) ->
            raise (Ast.StaticError (loc, str, None)))

  (* Todo @Nima: We should add error handling parts at the end of `translate_*` functions *)
end
(* Todo @Nima: There would be naming conflicts if the user writes a function in Rust with a name like `std_alloc_alloc`.
   A possible solution might be adding `crate` in front of local declarations. Another problem with names is that two paths
   like `a::mut_ptr::b` and `a::mut_ptr::b` both convert to `a_mut_ptr_b` *)

(* Todo @Nima: Unit type gets translated to an empty struct and Never (empty) type to an empty union.
   The latter is not true because an empty union type has a value. For now, we are preventing the production and consumption
   of padding chunks and chars predicates for empty structs and empty unions respectively when verifying Rust programs in
   the `produce_c_object` and `consume_c_object` functions in `verify_expr.ml`.
   For the Never type, we should add a specific type to VeriFast instead and extend the function `prover_type_of_type` to support it.
   Moreover, check for the correct behaviour of production and consumption of chars predicate for empty Rust unions. *)
