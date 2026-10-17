open Vf_mir_decoder
open Refinement_checker

let memoize f =
  let cache = Hashtbl.create 100 in
  fun x ->
    match Hashtbl.find_opt cache x with
    | Some y -> y
    | None ->
        let y = f x in
        Hashtbl.add cache x y;
        y

(** Ignore `/*@~mut@*/` directives *)
let ignore_directives = ref false
let check_first_fnmut_continue = ref false
let push xs_ref x = xs_ref := x :: !xs_ref
let rustc_args = ref []

let original_path, verified_path =
  let rec process_args = function
    | flag :: args when String.starts_with ~prefix:"--" flag -> (
        match flag :: args with
        | "--" :: [ original_path; verified_path ] ->
            (original_path, verified_path)
        | "--ignore-directives" :: args ->
          ignore_directives := true;
          process_args args
        | "--check-first-fnmut-continue" :: args ->
          check_first_fnmut_continue := true;
          process_args args
        | "--verbose" :: value :: args ->
            verbosity :=
              begin match int_of_string_opt value with
                None -> failwith "--verbose expects an integer argument"
              | Some n -> n
              end;
            process_args args
        | "--rustc-args" :: value :: args ->
            rustc_args := !rustc_args @ String.split_on_char ' ' value;
            process_args args
        | _ -> failwith ("No such flag: " ^ flag))
    | [ original_path; verified_path ] -> (original_path, verified_path)
    | _ ->
        print_endline
          "Usage: refinement_checker [--ignore-directives] [--check-first-fnmut-continue] [--verbose N] [--rustc-args ARGS] [--] <original_path> \
           <verified_path>\n\n\
           Checks that each behavior of each function in the original path is \
           also exhibited by the corresponding function in the verified path\n\n
           Options:\n\
               --ignore-directives     Ignore /*@~mut@*/ directives\n\
               --check-first-fnmut-continue\n\
                                      Check the source-bound first insert_tail FnMut unwind edge";
        exit 1
  in
  process_args (List.tl (Array.to_list Sys.argv))

let () =
  if !ignore_directives then
    push rustc_args "--vf-rust-mir-exporter:no-preprocess"
  else
    push rustc_args "--vf-rust-mir-exporter:preprocess-readonly"

let () = Perf.init_windows_error_mode ()

let original_vf_mir =
  decode_vf_mir @@ VfMirRd.VfMir.of_message @@ Frontend.get_vf_mir !rustc_args original_path

let verified_vf_mir =
  decode_vf_mir @@ VfMirRd.VfMir.of_message @@ Frontend.get_vf_mir !rustc_args verified_path

let ensure_unique_keys kvs =
  let keys_seen = Hashtbl.create (List.length kvs) in
  kvs |> List.map @@ fun (k, v) ->
    let seen = Hashtbl.find_all keys_seen k in
    Hashtbl.add keys_seen k ();
    if seen = [] then (k, v) else (Printf.sprintf "%s__%d" k (List.length seen), v)

(* Check, for each function body in original_vf_mir, that there is a matching function body in verified_vf_mir *)
let original_bodies =
  original_vf_mir.bodies
  |> List.map (fun body -> (canonicalize_def_path body.def_path, body))
  |> ensure_unique_keys

let verified_bodies =
  verified_vf_mir.bodies
  |> List.map (fun body -> (canonicalize_def_path body.def_path, body))
  |> ensure_unique_keys

let generated_glue_key = "__vf_generated_drop_glue"

let require_generated condition message =
  if not condition then error ("Generated DropGlue: " ^ message)

let one_generated_body unit_name bodies =
  let generated = List.filter (fun (_, body) -> body.generated_glue.enabled) bodies in
  match generated with
  | [] -> None
  | [(_, body)] ->
      require_generated (body.def_path = generated_glue_key &&
                         body.generated_glue.body_key = generated_glue_key)
        (unit_name ^ " has an unexpected generated body key");
      require_generated
        (List.length (List.filter (fun (_, b) ->
           b.def_path = generated_glue_key) bodies) = 1)
        (unit_name ^ " has a duplicate generated body key");
      Some body
  | _ -> error ("Generated DropGlue: " ^ unit_name ^ " has multiple tagged bodies")

let generated_original = one_generated_body "original" original_bodies
let generated_verified = one_generated_body "verified" verified_bodies

let check_generated_unit unit_name bodies body =
  let g = body.generated_glue in
  let nonempty name value =
    require_generated (value <> "") (unit_name ^ " has no " ^ name)
  in
  List.iter (fun (name, value) -> nonempty name value)
    ["guard path", g.guard_path; "guard hash", g.guard_hash;
     "glue path", g.glue_def_path; "glue hash", g.glue_def_hash;
     "selected drop path", g.selected_drop_path;
     "selected drop hash", g.selected_drop_hash;
     "selected source hash", g.selected_source_hash;
     "raw trait path", g.raw_trait_path;
     "raw trait hash", g.raw_trait_hash;
     "raw trait arguments", g.raw_trait_args];
  require_generated (g.instance_kind = "DropGlue" && g.instance_args <> [] &&
                     g.resolved_args = [] &&
                     g.glue_def_path = "core::ptr::drop_glue" &&
                     g.raw_trait_path = "core::ops::Drop::drop")
    (unit_name ^ " has an unsupported instance");
  require_generated (g.selected_source_phase = "Runtime(PostCleanup)" &&
                     g.mir_phase = "Runtime(Optimized)" &&
                     g.unwind_kind = "Continue" &&
                     g.normal_target = Stdint.Uint32.of_int 1)
    (unit_name ^ " has an unexpected MIR phase or control-flow edge");
  require_generated (body.def_path_hash = g.glue_def_hash &&
                     body.captured_mir_hash <> "" &&
                     body.captured_mir_phase = g.mir_phase)
    (unit_name ^ " generated body does not match its captured glue identity");
  require_generated (body.def_kind = Fn && body.visibility = Restricted &&
                     body.hir_generics.params = [] && body.generics = [] &&
                     body.impl_block_generics = [] && body.clauses = [] &&
                     body.impl_block_clauses = [] && body.ghost_stmts = [] &&
                     body.ghost_decl_blocks = [] && body.loop_spec_blocks = [] &&
                     body.var_debug_info = [] &&
                     body.contract.annotations = [] &&
                     not body.is_drop_fn && not body.is_trait_fn)
    (unit_name ^ " generated body has unsupported declarations");
  let selected = List.filter (fun (_, b) ->
    b.is_drop_fn && b.def_path = g.selected_drop_path &&
    b.def_path_hash = g.selected_drop_hash) bodies in
  let selected = match selected with
    | [(_, b)] -> b
    | _ -> error ("Generated DropGlue: " ^ unit_name ^
                  " must contain one checked selected Drop::drop body")
  in
  require_generated (selected.captured_mir_hash = g.selected_source_hash &&
                     selected.captured_mir_phase = g.selected_source_phase)
    (unit_name ^ " selected method does not match captured MIR");
  let drops = bodies |> List.concat_map (fun (_, b) ->
    b.basic_blocks |> List.filter_map (fun bb ->
      match bb.terminator.kind with
      | Drop d when d.generated_body_key <> "" -> Some (b, bb.is_cleanup, d)
      | _ -> None)) in
  let normal_drops = List.filter (fun (_, is_cleanup, _) -> not is_cleanup) drops in
  begin match normal_drops with
  | [(caller, _, _)] ->
      require_generated (List.for_all (fun (b, _, _) -> b.def_path = caller.def_path) drops)
        (unit_name ^ " tagged Drops occur in different callers");
      List.iter (fun (_, _, d) ->
      require_generated (d.generated_body_key = g.body_key &&
                         d.selected_drop_path = g.selected_drop_path &&
                         d.selected_drop_hash = g.selected_drop_hash &&
                         d.selected_guard_path = g.guard_path &&
                         d.is_bare_local && not d.is_replace &&
                         d.place.projection = [])
        (unit_name ^ " caller Drop does not bind the generated body");
      let guard_locals = List.filter (fun (local: Vf_mir_decoder.local_decl) ->
        local.id = d.place.local &&
        local.ty.kind = (match g.receiver_type.kind with
          | Ref {ty; _} -> ty.kind
          | _ -> Tuple [])) caller.local_decls in
      require_generated (List.length guard_locals = 1)
        (unit_name ^ " caller Drop place has the wrong guard type")) drops
  | _ -> error ("Generated DropGlue: " ^ unit_name ^
                " must contain exactly one normal tagged caller Drop")
  end

let check_generated_layout unit_name vf_mir body =
  let rec ind_list_to_list = function
    | Nil -> []
    | Cons {h; t} -> h :: ind_list_to_list t
  in
  let g = body.generated_glue in
  require_generated (vf_mir.target_triple = "x86_64-unknown-linux-gnu" &&
                     vf_mir.pointer_width = 64)
    (unit_name ^ " has the wrong target");
  let guards = List.filter (fun (adt: adt_def) ->
    adt.id.name = g.guard_path && adt.is_local &&
    adt.has_concrete_guard_layout &&
    adt.concrete_guard_def_path = g.guard_path &&
    adt.concrete_guard_def_path_hash = g.guard_hash)
    (ind_list_to_list vf_mir.adt_defs) in
  match guards with
  | [adt] ->
      let u64: Vf_mir_decoder.ty = {kind=UInt U64} in
      begin match adt.variants with
      | [variant] ->
          begin match variant.fields with
          | [src; dst; len] ->
              require_generated
                (src.name.name = "src" && dst.name.name = "dst" &&
                 len.name.name = "len" &&
                 src.ty.kind = RawPtr {mutability=Not; ty=u64} &&
                 dst.ty.kind = RawPtr {mutability=Mut; ty=u64} &&
                 len.ty.kind = UInt USize &&
                 adt.concrete_guard_size_bytes = Stdint.Uint64.of_int 24 &&
                 adt.concrete_guard_align_bytes = Stdint.Uint64.of_int 8 &&
                 adt.concrete_guard_field_offsets = ["0"; "8"; "16"] &&
                 adt.concrete_guard_field_sizes = ["8"; "8"; "8"])
                (unit_name ^ " has a different concrete guard layout")
          | _ -> error ("Generated DropGlue: " ^ unit_name ^ " guard has wrong fields")
          end
      | _ -> error ("Generated DropGlue: " ^ unit_name ^ " guard has wrong variants")
      end
  | _ -> error ("Generated DropGlue: " ^ unit_name ^
                " must contain one matching local concrete guard")

let check_generated_shape unit_name body =
  let g = body.generated_glue in
  let bad detail = error ("Generated DropGlue: " ^ unit_name ^ " " ^ detail) in
  let local name (p: Vf_mir_decoder.place) =
    p.local.name = name && p.projection = [] && p.kind = Other in
  let unit_ty (ty: Vf_mir_decoder.ty) = ty.kind = Tuple [] in
  begin match body.inputs, body.local_decls with
  | [input], [r; self; copied; result] ->
      if input <> g.receiver_type || not (unit_ty body.output) ||
         not (unit_ty r.ty && unit_ty result.ty) ||
         self.ty <> input || copied.ty <> input ||
         r.id.name <> "_0" || self.id.name <> "_1" ||
         copied.id.name <> "_2" || result.id.name <> "_3" ||
         List.map (fun (local: local_decl) -> local.mutability) body.local_decls <>
           [Mut; Not; Mut; Mut] then
        bad "has a different signature or local layout";
      begin match input.kind with
      | Ref {mutability=Mut; ty={kind=Adt guard}; _}
          when guard.id.name = g.guard_path && guard.substs = [] &&
               g.instance_args = [{kind=Type {kind=Adt guard}}] -> ()
      | _ -> bad "receiver is not &mut of the selected guard"
      end
  | _ -> bad "must have exactly one input and four locals"
  end;
  begin match body.basic_blocks with
  | [bb0; bb1] when bb0.id.index = Stdint.Uint32.of_int 0 &&
                     bb1.id.index = Stdint.Uint32.of_int 1 &&
                     not bb0.is_cleanup && not bb1.is_cleanup ->
      begin match bb0.statements with
      | [{kind=Assign {lhs_place; rhs_rvalue=Use (Copy source)}; _}]
          when local "_2" lhs_place && local "_1" source -> ()
      | _ -> bad "bb0 must contain only _2 = copy _1"
      end;
      begin match bb0.terminator.kind with
      | Call call ->
          begin match call.func with
          | Constant {const=Val {const_value=ZeroSized;
                                 ty={kind=FnDef fn}}; _}
              when fn.id.name = g.raw_trait_path &&
                   fn.substs = g.instance_args &&
                   fn.late_bound_generic_param_count = 1 -> ()
          | _ -> bad "call is not the recorded raw trait FnDef"
          end;
          begin match call.args, call.target, call.unwind_action with
          | [Move arg], Something target, Continue
              when local "_2" arg && local "_3" call.destination &&
                   target.index = g.normal_target &&
                   call.ghost_generic_arg_list = Nothing -> ()
          | _ -> bad "call operands, destination, target, or unwind differ"
          end
      | _ -> bad "bb0 must end in the recorded trait call"
      end;
      require_generated (bb1.statements = [] && bb1.terminator.kind = Return)
        (unit_name ^ " bb1 must contain only Return")
  | _ -> bad "must have exactly the observed two-block CFG"
  end

let check_generated_pair body0 body1 =
  check_generated_unit "original" original_bodies body0;
  check_generated_unit "verified" verified_bodies body1;
  check_generated_layout "original" original_vf_mir body0;
  check_generated_layout "verified" verified_vf_mir body1;
  check_generated_shape "original" body0;
  check_generated_shape "verified" body1;
  let g0, g1 = body0.generated_glue, body1.generated_glue in
  require_generated
    (g0.body_key = g1.body_key && g0.guard_path = g1.guard_path &&
     g0.glue_def_path = g1.glue_def_path &&
     g0.instance_kind = g1.instance_kind &&
     g0.instance_args = g1.instance_args &&
     g0.selected_drop_path = g1.selected_drop_path &&
     g0.resolved_args = g1.resolved_args &&
     g0.selected_source_phase = g1.selected_source_phase &&
     g0.raw_trait_path = g1.raw_trait_path &&
     g0.raw_trait_args = g1.raw_trait_args &&
     g0.normal_target = g1.normal_target &&
     g0.unwind_kind = g1.unwind_kind && g0.mir_phase = g1.mir_phase &&
     g0.receiver_type = g1.receiver_type)
    "original and verified descriptors differ";
  let without_spans (b: body) =
    let local_decls = List.map (fun (d: local_decl) ->
      {d with source_info={span=Dummy}}) b.local_decls in
    let basic_blocks = List.map (fun (bb: basic_block) ->
      let statements = List.map (fun (s: statement) ->
        {s with source_info={span=Dummy}}) bb.statements in
      let kind = match bb.terminator.kind with
        | Call call ->
            let func: Vf_mir_decoder.operand = match call.func with
              | Constant c -> Constant {c with span=Dummy}
              | operand -> operand
            in
            Call {call with func; call_span=Dummy}
        | kind -> kind
      in
      let terminator = {bb.terminator with source_info={span=Dummy}; kind} in
      {bb with statements; terminator}) b.basic_blocks in
    local_decls, basic_blocks
  in
  require_generated (without_spans body0 = without_spans body1)
    "original and verified MIR differ outside source spans"

let get_line_offsets text =
  let rec get_line_offsets' text offset acc =
    match String.index_from_opt text offset '\n' with
    | None -> List.rev acc
    | Some i -> get_line_offsets' text (i + 1) ((i + 1) :: acc)
  in
  get_line_offsets' text 0 [ 0 ]

let load_file_core path =
  let chan = open_in path in
  let contents = Frontend.input_fully chan in
  close_in chan;
  let line_offsets = Array.of_list (get_line_offsets contents) in
  (contents, line_offsets)

let load_file = memoize load_file_core
let decode_body_span (body: body) = decode_span body.span

let load_span_snippet span =
  let (path, start_line, start_col), (_, end_line, end_col) = span in
  let contents, line_offsets = load_file path in
  let start_offset = line_offsets.(start_line - 1) + start_col in
  let end_offset = line_offsets.(end_line - 1) + end_col in
  String.sub contents start_offset (end_offset - start_offset)

let fnmut_call_sites (body: body) =
  body.basic_blocks
  |> List.filter_map (fun bb ->
       match bb.terminator.kind with
       | Call call ->
           begin match call.func with
           | Constant {const=Val {ty={kind=FnDef fn}; _}; _}
               when String.ends_with ~suffix:"FnMut::call_mut" fn.id.name ->
               Some (decode_span bb.terminator.source_info.span, bb, call)
           | _ -> None
           end
       | _ -> None)
  |> List.sort (fun (span0, _, _) (span1, _, _) -> compare span0 span1)

let source_has_def_path_name body name =
  body.def_path = name || String.ends_with ~suffix:("::" ^ name) body.def_path

let skip_whitespace contents offset =
  let rec skip_whitespace' offset =
    if offset = String.length contents then offset
    else
      match contents.[offset] with
      | ' ' | '\t' | '\n' | '\r' -> skip_whitespace' (offset + 1)
      | '/' ->
          if offset + 1 < String.length contents then
            match contents.[offset + 1] with
            | '/' ->
                let rec skip_comment offset =
                  if offset = String.length contents then offset
                  else
                    match contents.[offset] with
                    | '\n' -> skip_whitespace' (offset + 1)
                    | _ -> skip_comment (offset + 1)
                in
                skip_comment (offset + 2)
            | '*' ->
                let rec skip_comment offset nesting_depth =
                  if offset = String.length contents then
                    failwith "Unexpected EOF in comment"
                  else
                    match contents.[offset] with
                    | '*' ->
                        if offset + 1 < String.length contents then
                          match contents.[offset + 1] with
                          | '/' ->
                              if nesting_depth = 1 then
                                skip_whitespace' (offset + 2)
                              else skip_comment (offset + 2) (nesting_depth - 1)
                          | _ -> skip_comment (offset + 1) nesting_depth
                        else failwith "Unexpected EOF in comment"
                    | '/' ->
                        (* Handle nested comments *)
                        if offset + 1 < String.length contents then
                          match contents.[offset + 1] with
                          | '*' -> skip_comment (offset + 2) (nesting_depth + 1)
                          | _ -> skip_comment (offset + 1) nesting_depth
                        else failwith "Unexpected EOF in comment"
                    | _ -> skip_comment (offset + 1) nesting_depth
                in
                skip_comment (offset + 2) 1
            | _ -> offset
          else offset
      | _ -> offset
  in
  skip_whitespace' offset


let require_first_callback_source_shape (body: body) side =
  let fail detail =
    failwith ("--check-first-fnmut-continue " ^ side ^ " source admission: " ^ detail)
  in
  let ((path, _, _), _) = decode_body_span body in
  let prefix = source_has_def_path_name body "insert_tail_first_callback_prefix" in
  if not prefix && not (source_has_def_path_name body "insert_tail") then
    fail "body path is neither insert_tail nor the named callback prefix";
  let source = load_span_snippet (decode_body_span body) in
  let locate token =
    match Str.search_forward (Str.regexp_string token) source 0 with
    | offset -> offset
    | exception Not_found -> fail ("source body is missing " ^ token)
  in
  let contains token =
    match Str.search_forward (Str.regexp_string token) source 0 with
    | _ -> true
    | exception Not_found -> false
  in
  ignore (locate (if prefix then "fn insert_tail_first_callback_prefix" else "fn insert_tail"));
  let callback_offset = locate "if !is_less" in
  let after_callback_head = callback_offset + String.length "if !is_less" in
  let callback_arg_start = skip_whitespace source after_callback_head in
  if callback_arg_start >= String.length source || source.[callback_arg_start] <> '(' then
    fail "first source callback is not the actual is_less invocation";
  let require_after_cursor token cursor =
    let cursor = skip_whitespace source cursor in
    if cursor + String.length token > String.length source ||
       String.sub source cursor (String.length token) <> token then
      fail ("first source callback is missing " ^ token);
    cursor + String.length token
  in
  let after_args = require_after_cursor "(" callback_arg_start in
  let after_tail = require_after_cursor "&*tail" after_args in
  let after_comma = require_after_cursor "," after_tail in
  let after_sift = require_after_cursor "&*sift" after_comma in
  ignore (require_after_cursor ")" after_sift);
  if prefix then begin
    ignore (locate "tail.sub(1)");
    ignore (locate "return;");
    if contains "tail.read" || contains "CopyOnDrop" then
      fail "callback prefix includes tail.read or guard construction"
  end else begin
    let read_offset = locate "let tmp = ManuallyDrop::new(tail.read())" in
    let guard_offset = locate "let mut gap_guard = CopyOnDrop" in
    if not (callback_offset < read_offset && read_offset < guard_offset) then
      fail "first callback is not before tail.read and guard construction"
  end;
  let calls = fnmut_call_sites body in
  let source_offset_of_span span =
    let (first_path, first_line, first_col), _ = span in
    let _, offsets = load_file path in
    let (body_start_path, body_start_line, body_start_col), _ = decode_body_span body in
    if first_path <> path || body_start_path <> path ||
       first_line <= 0 || first_line > Array.length offsets then
      fail "first callback has no source location in this body";
    offsets.(first_line - 1) + first_col -
      (offsets.(body_start_line - 1) + body_start_col)
  in
  match calls with
  | [first_span, _, _] when prefix ->
      let first_offset = source_offset_of_span first_span in
      if first_offset < callback_offset || first_offset >= String.length source then
        fail "callback-prefix MIR call span is not inside the source comparator expression";
      first_span
  | (first_span, _, _) :: (late_span, _, _) :: _ when not prefix ->
      if compare first_span late_span >= 0 then fail "callback MIR order is ambiguous";
      let first_offset = source_offset_of_span first_span in
      let read_offset = locate "let tmp = ManuallyDrop::new(tail.read())" in
      if first_offset < callback_offset || first_offset >= read_offset then
        fail "first callback call span is not before tail.read";
      first_span
  | _ -> fail "body does not contain a unique first and later FnMut::call_mut"

let () =
  if !check_first_fnmut_continue then begin
    Refinement_checker.first_fnmut_continue_check := true;
    let candidates bodies =
      List.filter (fun (_key, body) ->
        (source_has_def_path_name body "insert_tail" ||
         source_has_def_path_name body "insert_tail_first_callback_prefix")) bodies
    in
    let original = match candidates original_bodies with
      | [candidate] -> candidate
      | _ -> failwith "--check-first-fnmut-continue requires exactly one source-bound insert_tail or named prefix"
    in
    let verified = match candidates verified_bodies with
      | [candidate] -> candidate
      | _ -> failwith "--check-first-fnmut-continue requires exactly one source-bound verified insert_tail or named prefix"
    in
    let key0, body0 = original in
    let key1, body1 = verified in
    if key0 <> key1 then failwith "--check-first-fnmut-continue original and verified insert_tail paths differ";
    (* Each admission below loads the actual file named by that body's MIR
       span and binds the selected Call span into that same file.  The runner
       pins the paired source blob; a basename match is not source identity. *)
    let span0 = require_first_callback_source_shape body0 "original" in
    let span1 = require_first_callback_source_shape body1 "verified" in
    Refinement_checker.first_fnmut_continue_target := Some (key0, span0, span1)
  end

let closure_parent_def_path def_path =
  (* Find the final : in the def_path *)
  let last_colon = String.rindex def_path ':' in
  assert (String.sub def_path (last_colon - 1) 11 = "::{closure#");
  String.sub def_path 0 (last_colon - 1)

let rec bodies_are_identical def_path body0 body1 =
  body0.def_kind = body1.def_kind &&
  if body0.def_kind = Closure then
    let parent_def_path = closure_parent_def_path def_path in
    match List.assoc_opt parent_def_path original_bodies, List.assoc_opt parent_def_path verified_bodies with
    | Some parent_body0, Some parent_body1 ->
      bodies_are_identical parent_def_path parent_body0 parent_body1
    | _ -> false
  else
    not body0.is_from_expansion && not body1.is_from_expansion &&
    let snippet0 = load_span_snippet (decode_body_span body0) in
    let snippet1 = load_span_snippet (decode_body_span body1) in
    snippet0 = snippet1

let wrapper_fn_spans =
  verified_bodies |> List.map (fun (fn, body) ->
    if String.ends_with ~suffix:"__VeriFast_wrapper" fn then
      [decode_body_span body]
    else []) |> List.flatten

let original_checked_spans = ref []
let verified_checked_spans = ref wrapper_fn_spans

let check_body_refines_body def_path body verified_body =
  let is_first_target =
    match !Refinement_checker.first_fnmut_continue_target with
    | Some (target_path, _, _) -> target_path = def_path
    | None -> false
  in
  if body.generated_glue.enabled || verified_body.generated_glue.enabled then begin
    require_generated (body.generated_glue.enabled && verified_body.generated_glue.enabled)
      "tag is present on only one side";
    check_generated_pair body verified_body;
    check_body_refines_body original_bodies verified_bodies def_path body verified_body
  end else if not is_first_target && bodies_are_identical def_path body verified_body then begin
    if !verbosity >= verbosity_body then
      Printf.printf "Function bodies for %s are identical\n" def_path
  end else (
    if !verbosity >= verbosity_body then
      Printf.printf
        "Function bodies for %s are different; checking refinement...\n" def_path;
    check_body_refines_body original_bodies verified_bodies def_path body verified_body;
    push original_checked_spans (decode_body_span body);
    push verified_checked_spans (decode_body_span verified_body))


let rec skip_whitespace_and_checked_ranges contents offset checked_ranges =
  let offset = skip_whitespace contents offset in
  match checked_ranges with
  | (start, end_) :: checked_ranges when start <= offset ->
    skip_whitespace_and_checked_ranges contents (max offset end_) checked_ranges
  | _ -> offset, checked_ranges

(* Checks that the two files are identical, after collapsing whitespace and spans checked by the refinement checker *)
let check_files_match (path0, path1) =
  if !verbosity >= verbosity_body then
    Printf.printf "Checking that, apart from checked functions and comments, %s and %s are identical\n" path0 path1;
  let contents0, line_offsets0 = load_file path0 in
  let contents1, line_offsets1 = load_file path1 in
  let checked_ranges0 =
    List.filter
      (fun ((path, start_line, start_col), (_, end_line, end_col)) ->
        path = path0)
      !original_checked_spans
  in
  let checked_ranges1 =
    List.filter
      (fun ((path, start_line, start_col), (_, end_line, end_col)) ->
        path = path1)
      !verified_checked_spans
  in
  let checked_ranges0 =
    List.map
      (fun ((_, start_line, start_col), (_, end_line, end_col)) ->
        ( line_offsets0.(start_line - 1) + start_col,
          line_offsets0.(end_line - 1) + end_col ))
      checked_ranges0
  in
  let checked_ranges1 =
    List.map
      (fun ((_, start_line, start_col), (_, end_line, end_col)) ->
        ( line_offsets1.(start_line - 1) + start_col,
          line_offsets1.(end_line - 1) + end_col ))
      checked_ranges1
  in
  let checked_ranges0 = List.sort compare checked_ranges0 in
  let checked_ranges1 = List.sort compare checked_ranges1 in
  let rec iter offset0 offset1 checked_ranges0 checked_ranges1 =
    let offset0', checked_ranges0 = skip_whitespace_and_checked_ranges contents0 offset0 checked_ranges0 in
    let offset1', checked_ranges1 = skip_whitespace_and_checked_ranges contents1 offset1 checked_ranges1 in
    if offset0' = offset0 <> (offset1' = offset1) then
      failwith
        (Printf.sprintf
           "Comparing %s to %s: Whitespace mismatch at offset %d/%d" path0 path1
           offset0 offset1);
    let offset0, offset1 = (offset0', offset1') in
    if offset0 = String.length contents0 then
      if offset1 = String.length contents1 then (
        if checked_ranges0 <> [] || checked_ranges1 <> [] then
          failwith
            (Printf.sprintf "Comparing %s to %s: Unused checked ranges remain: %s vs %s"
               path0 path1 (String.concat ", " (List.map (fun (start, end_) -> Printf.sprintf "(%d, %d)" start end_) checked_ranges0))
               (String.concat ", " (List.map (fun (start, end_) -> Printf.sprintf "(%d, %d)" start end_) checked_ranges1)));
        ())
      else
        failwith
          (Printf.sprintf "Comparing %s to %s: Unexpected EOF in %s"
              path0 path1 path1)
    else if offset1 = String.length contents1 then
      failwith
        (Printf.sprintf "Comparing %s to %s: Unexpected EOF in %s" path0
            path1 path0)
    else (
      if contents0.[offset0] <> contents1.[offset1] then
        failwith
          (Printf.sprintf
              "Comparing %s to %s: Mismatch at offset %d/%d: %c vs %c"
              path0 path1 offset0 offset1 contents0.[offset0]
              contents1.[offset1]);
      iter (offset0 + 1) (offset1 + 1) checked_ranges0 checked_ranges1)
  in
  iter 0 0 checked_ranges0 checked_ranges1

let check_files_match = memoize check_files_match

let rec check_module module0 module1 =
  let (path0, _, _), _ = decode_span module0.body_span in
  let (path1, _, _), _ = decode_span module1.body_span in
  check_files_match (path0, path1);
  let submodules0 = module0.submodules in
  let submodules1 = module1.submodules in
  List.iter2 check_module submodules0 submodules1

let check_bodies () =
  let has_generated_drop bodies =
    List.exists (fun (_, body) ->
      List.exists (fun bb -> match bb.terminator.kind with
        | Drop d -> d.generated_body_key <> ""
        | _ -> false) body.basic_blocks) bodies
  in
  begin match generated_original, generated_verified with
  | None, None ->
      require_generated
        (not (has_generated_drop original_bodies) &&
         not (has_generated_drop verified_bodies))
        "a tagged caller Drop has no generated body"
  | Some _, Some _ -> ()
  | _ -> error "Generated DropGlue: body missing from one exported unit"
  end;
  original_bodies
  |> List.iter @@ fun (def_path, body) ->
     match List.assoc_opt def_path verified_bodies with
     | None ->
        if body.visibility = Restricted && not body.generated_glue.enabled then
          () (* If a private function of the original program does not appear in the verified program,
                it must be the case that all calls of that function were inlined. *)
        else
          error
            (Printf.sprintf "Function body %s not found in verified path"
               def_path)
     | Some verified_body -> check_body_refines_body def_path body verified_body

let check_modules () =
  check_files_match (original_path, verified_path);
  let modules0 = original_vf_mir.modules in
  let modules1 = verified_vf_mir.modules in
  List.iter2 check_module modules0 modules1

let () =
  try
    check_bodies ();
    check_modules ();
    if !check_first_fnmut_continue then begin
      if not !Refinement_checker.first_fnmut_continue_receipt then
        failwith "--check-first-fnmut-continue requested but the selected first edge was not checked";
      let target_name = match !Refinement_checker.first_fnmut_continue_target with
        | Some (path, _, _) when path = "insert_tail_first_callback_prefix" ||
                                  String.ends_with ~suffix:"::insert_tail_first_callback_prefix" path ->
            "insert_tail_first_callback_prefix"
        | Some _ -> "insert_tail"
        | None -> failwith "--check-first-fnmut-continue has no admitted source target"
      in
      Printf.printf "QUALIFIED_FIRST_FNMUT_CONTINUE_EDGE: source-bound %s first FnMut::call_mut operands refined; original and verified unwind are Continue\n" target_name
    end;
    Printf.printf "No refinement errors found\n"
  with RefinementCheckFailure msg ->
    print_endline msg;
    exit 1
    
