# R23 source-level array borrow adapter design

Status: design contract only; implementation and proof acceptance are not
established. This is an opt-in, default-off translation path for one original
caller expression. It does not change Rust runtime code or add an ownership,
aliasing, lifetime, or memory premise.

## Applicability

An adapter plan is accepted only for one marked source site in the registered
caller body. The source site is the original `values.as_mut_ptr()` expression.
The bound MIR evidence must show, at the same source span and body binding:

1. One mutable `Ref` whose exact place is the bare local `values` and whose
   exact pointee is `[u64; 3]`.
2. The immediately corresponding pointer cast is
   `PointerCoercion::Unsize`, from `&mut [u64; 3]` to `&mut [u64]`.
   `ArrayToPointer`, a raw-pointer cast, an address match, or a similar span
   does not qualify.
3. The unique receiver and call dataflow is that result passed to the exact
   `core::slice::<impl [u64]>::as_mut_ptr` receiver and no alias escapes or
   other use of the reference temporaries.
4. Actual array length is exactly three, and the typed MIR lifetime identity,
   when present, is bound to the same source scope and variable. An erased or
   absent region is never interpreted as a logical Rust lifetime.
5. The source contains exactly one adapter marker, the marker's named local
   resolves to this body-local place, and its lexical scope is the unique
   checked source interval. Missing, duplicate, malformed, type-mismatched,
   or non-matching evidence is a hard error; the default path remains off.

The explicit ghost lifetime name in checked source annotations may be used as
the logical name for this unique interval only after the conditions above and
strict lifetime/no-escape checking succeed. It does not assert equality with an
erased compiler region. Any representation gap that requires such equality,
extra authority, or an unchecked bridge is a stop condition.

## Resource invariant and translation

The translator must use the existing RustBelt full-borrow protocol. Starting
the fresh logical lifetime uses checked `begin_lifetime`; `borrow(k, P)` moves
the exact source content `P()` into `full_borrow(k, P)` plus
`borrow_end_token(k, P)`. For this caller, `P()` is established from the
existing checked `[u64; 3]` and `u64` ownership/conversion lemmas, including
the actual array length and all three element owners. Slice metadata is made
with existing `slice_from_raw_parts_mut(data, 3)` and the checked array-to-slice
content conversion. The translator requires the exporter's complete typed MIR
projection for the actual std `as_mut_ptr` body and compares it with the
paired checked helper body's straight-line typed cast projection before
redirecting this call. The helper contract preserves the full borrow and
returns exactly the data component of the already checked slice. No std callee
name-only summary is used.

On every normal and unwind outcome, the same `k` and exact `P` are restored:
end the logical lifetime, use `borrow_end(k, P)`, then reopen/convert the same
content to its original array ownership. Restoration follows the actual
normal/unwind CFG edges and cannot depend on `StorageDead`, NLL `loan_killed_at`,
or equal addresses. The insert-tail call stays outside a `let_lft` scope unless
both real outcomes pass strict no-exception-escape checking and have checked
restoration. Do not mix TreeBorrows `create_ref_mut`/`ref_mut_end_token` with
RustBelt `full_borrow`.

## Marker / annotation interface proposed to the caller owner

Place two zero-authority line markers around the original statement. `begin` is
the result binder of that runtime statement, so it cannot appear in the
pre-marker:

```rust
//@ r23_source_array_borrow_adapter(r23_borrow_k, values);
//@ let r23_array_p = &values as *mut [u64; 3];
//@ assert array::<u64>(r23_array_p as *u64, 3, ?r23_borrow_values);
//@ array_to_Array(r23_array_p);
//@ assert *r23_array_p |-> ?r23_borrow_array;
//@ r9_make_u64_owners(t, Array_elems(r23_borrow_array));
//@ close r23_u64_array3_own(t, r23_borrow_array);
//@ close r23_u64_array3_fbc(t, r23_array_p)();
//@ borrow(r23_borrow_k, r23_u64_array3_fbc(t, r23_array_p));
//@ let_lft 'r23_borrow = r23_borrow_k;
let begin = values.as_mut_ptr();
//@ r23_source_array_borrow_adapter_end(r23_borrow_k, values, begin, r23_borrow_values);
//@ end_lifetime(r23_borrow_k);
//@ borrow_end(r23_borrow_k, r23_u64_array3_fbc(t, r23_array_p));
//@ r23_dispose_dead_array3_borrow(r23_borrow_k, t, r23_array_p);
//@ open r23_u64_array3_fbc(t, r23_array_p)();
//@ assert *r23_array_p |-> ?r23_restored_array;
//@ open r23_u64_array3_own(t, r23_restored_array);
//@ r9_drop_u64_owners(t, Array_elems(r23_restored_array));
//@ Array_to_array(r23_array_p);
```

`values` is the exact body-local array place. `begin` is the source result
pointer and `r23_borrow_values` is an existing array/content state binder used
by checked assertions. The translator validates the flat pre/post command
sequences, binds the unique `let_lft` declaration to the source interval, and
moves only the selected Ref/Unsize temporary declarations into that strict
scope. Those proof AST types use `'r23_borrow`; exported MIR metadata remains
unchanged, and no erased compiler region is equated with that logical name.
Markers are metadata only and grant no permissions. On method unwind,
translation restores the slice borrow, exits the strict scope, runs the checked
post sequence, converts the restored physical array for the original cleanup,
and then executes the original unwind action.

## Controls and invariant checks

Keep the feature disabled unless the exact marker and per-profile opt-in are
both present. Preserve the old translation for all unmarked code. Add fixtures
for the one accepted exact chain and rejection of absent/duplicate markers,
wrong local, wrong pointee/element/length, shared mutability, wrong coercion,
raw pointer route, receiver mismatch, escaping/reused reference temporary,
ambiguous body/span, absent typed identity without a valid explicit source
scope, and malformed/duplicate annotation blocks. Include normal, panic,
Drop, and Resume source shapes and ensure the adapter only wraps the two
existing checked outcome branches. Preserve R8 RawPtr/place/origin controls,
R19 normal/unwind cleanup, and all existing targets, posts, generic signatures,
and CFG edges.

## Unresolved implementation boundary

The owner supplied the following narrow checked representation in
`r23-array3-borrow-content.rs`: `r23_u64_array3_own(t, a) =
foreach(Array_elems::<u64, 3>(a), own::<u64>(t))` and
`r23_u64_array3_fbc(t, p)() = *p |-> ?a &*& r23_u64_array3_own(t, a)`.
The adapter may select these only for exact `[u64; 3]` in the exact opted-in
body. `shr`, other element/length arrays, and generic array support stay
unsupported. Checked bridges use `Array_to_array` forward and `array_to_Array`
plus rebuilt element owners on reverse; no `Array_elems(Array_of_elems(xs))`
equality is assumed.

Current source-route evidence still must establish that the original caller's
Ref -> Unsize -> `as_mut_ptr` receiver sequence has the exact exported shape
and that the strict scope has no escape. If compiler region identity is
erased, the explicit source scope binds only this unique checked interval; it
does not equate the erased region with the logical name. These remain
conditions, not proof results. The main agent owns the canonical-original-
runtime diagnostic and checked proof annotations.

## Checked helper lifetime binding correction

The paired helper keeps its existing `fn<'a>(s: &'a mut [u64])` signature.
The exporter populates `Body.generics` from `tcx.generics_of(def_id).own_params`,
which describes early-bound item parameters; this input-only `'a` is
late-bound and therefore is not expected in that list. Helper admission must
require `Body.generics` to be empty and validate the exact source-declared
HIR generic list as one plain lifetime named `'a`. The check rejects other HIR
parameters, early-bound parameters, or missing/renamed source lifetimes; it
does not infer lifetime identity from MIR regions or change the checked
borrow/return contract. The helper's full typed signature and cast-body
comparison remain mandatory. This is a binding check for the existing
source declaration, not a new lifetime or authority premise.
