module VfMirStub = Vf_mir.Make (Capnp.BytesMessage)
module VfMirRd = VfMirStub.Reader

(* Util *)
module Int128Rd = VfMirStub.Reader.Int128
module UInt128Rd = VfMirStub.Reader.UInt128
module OptionRd = VfMirStub.Reader.Option
module IndListRd = VfMirStub.Reader.IndList
module TextWrapperRd = VfMirStub.Reader.TextWrapper

(* Source Spans *)
module SpanDataRd = VfMirStub.Reader.SpanData
module LocRd = VfMirStub.Reader.Loc
module SourceFileRd = VfMirStub.Reader.SourceFile
module FileNameRd = VfMirStub.Reader.FileName
module RealFileNameRd = VfMirStub.Reader.RealFileName
module CharPosRd = VfMirStub.Reader.CharPos

(* Global *)
module MutabilityRd = VfMirStub.Reader.Mutability
module SymbolRd = VfMirStub.Reader.Symbol
module AnnotationRd = VfMirStub.Reader.Annotation
module UnsafetyRd = VfMirStub.Reader.Unsafety
module IdentRd = VfMirStub.Reader.Ident
module VisibilityRd = VfMirStub.Reader.Visibility
module VarianceRd = VfMirStub.Reader.Variance

(* Hir *)
module HirRd = VfMirStub.Reader.Hir
module HirGenericsRd = HirRd.Generics
module HirGenericParamRd = HirGenericsRd.GenericParam
module HirGenericParamNameRd = HirGenericParamRd.ParamName
module HirGenericParamKindRd = HirGenericParamRd.GenericParamKind

(* Bodies *)
module BodyRd = VfMirStub.Reader.Body
module TraitRd = VfMirStub.Reader.Trait
module TraitImplRd = VfMirStub.Reader.TraitImpl
module ContractRd = VfMirStub.Reader.Contract
module LocalDeclRd = VfMirStub.Reader.LocalDecl
module LocalDeclIdRd = VfMirStub.Reader.LocalDeclId
module BasicBlockRd = VfMirStub.Reader.BasicBlock
module BasicBlockIdRd = VfMirStub.Reader.BasicBlockId
module TerminatorRd = VfMirStub.Reader.Terminator
module TerminatorKindRd = VfMirStub.Reader.TerminatorKind
module UnwindActionRd = VfMirStub.Reader.UnwindAction
module FnCallDataRd = TerminatorKindRd.FnCallData
module R23SliceProjectionRd = FnCallDataRd.R23SliceProjection
module R23SliceProjectionGenericBindingRd = R23SliceProjectionRd.GenericBinding
module DropDataRd = TerminatorKindRd.DropData
module AssertDataRd = TerminatorKindRd.AssertData
module OperandRd = VfMirStub.Reader.Operand
module ConstOperandRd = VfMirStub.Reader.ConstOperand
module PlaceRd = VfMirStub.Reader.Place
module PlaceElementRd = VfMirStub.Reader.PlaceElem
module PlaceKindRd = VfMirStub.Reader.PlaceKind
module StatementRd = VfMirStub.Reader.Statement
module StatementKindRd = VfMirStub.Reader.StatementKind
module AssignDataRd = StatementKindRd.AssignData
module RvalueRd = VfMirStub.Reader.Rvalue
module SourceInfoRd = VfMirStub.Reader.SourceInfo
module SwitchIntDataRd = TerminatorKindRd.SwitchIntData
module VarDebugInfoRd = VfMirStub.Reader.VarDebugInfo
module VarDebugInfoContentsRd = VfMirStub.Reader.VarDebugInfoContents
module ConstValueRd = VfMirStub.Reader.ConstValue
module ScalarRd = VfMirStub.Reader.Scalar
module BinaryOpDataRd = RvalueRd.BinaryOpData
module UnaryOpDataRd = RvalueRd.UnaryOpData
module BinOpRd = BinaryOpDataRd.BinOp
module UnOpRd = UnaryOpDataRd.UnOp
module AggregateDataRd = RvalueRd.AggregateData
module AggregateKindRd = VfMirStub.Reader.AggregateKind
module CastDataRd = RvalueRd.CastData
module RefDataRd = RvalueRd.RefData
module RefBorrowKindRd = RefDataRd.BorrowKind
module RawPtrDataRd = RvalueRd.RawPtrData
module RawPtrKindRd = VfMirStub.Reader.RawPtrKind
module DiscriminantDataRd = RvalueRd.DiscriminantData
module PointerCoercionDataRd = VfMirStub.Reader.PointerCoercionData
module PointerCoercionKindRd = PointerCoercionDataRd.Kind
module PointerCoercionSourceRd = PointerCoercionDataRd.CoercionSource

(* Types *)
module TyRd = VfMirStub.Reader.Ty
module IntTyRd = VfMirStub.Reader.IntTy
module UIntTyRd = VfMirStub.Reader.UIntTy
module TyKindRd = VfMirStub.Reader.TyKind
module ArrayTyRd = TyKindRd.ArrayTy
module RawPtrTyRd = TyKindRd.RawPtrTy
module CastKindRd = VfMirStub.Reader.CastKind
module AdtTyRd = TyKindRd.AdtTy
module AdtKindRd = VfMirStub.Reader.AdtKind
module AdtDefIdRd = VfMirStub.Reader.AdtDefId
module FnDefTyRd = TyKindRd.FnDefTy
module FnPtrTyRd = TyKindRd.FnPtrTy
module FnDefIdRd = VfMirStub.Reader.FnDefId
module GenArgRd = VfMirStub.Reader.GenericArg
module GenArgKindRd = VfMirStub.Reader.GenericArgKind
module RefTyRd = TyKindRd.RefTy
module AdtDefRd = VfMirStub.Reader.AdtDef
module VariantDefRd = VfMirStub.Reader.VariantDef
module FieldDefRd = VariantDefRd.FieldDef
module RegionRd = VfMirStub.Reader.Region
module RegionIdentityRd = RegionRd.Identity
module RegionInferenceVariableRd = RegionRd.InferenceVariable
module GenericParamDefRd = VfMirStub.Reader.GenericParamDef
module GenericParamDefKindRd = VfMirStub.Reader.GenericParamDefKind

(* Builder *)
module TyBd = VfMirStub.Builder.Ty
