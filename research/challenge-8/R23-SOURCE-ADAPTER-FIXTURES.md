# R23 source adapter admission fixtures

These are static control cases for the default-off translator plan. They are
not verifier results. The accepted case uses the exact line marker and checked
command envelope in `R23-SOURCE-ADAPTER-DESIGN.md`.

| Fixture | Change from accepted source/MIR chain | Expected adapter result |
|---|---|---|
| `accepted_array3_u64` | Mutable Ref of bare `[u64; 3]`, implicit PointerCoercion::Unsize to `&mut [u64]`, unique `as_mut_ptr` receiver and checked owner envelope | Admit only with opt-in and exactly one marker pair |
| `missing_marker` | Remove either marker | Keep default legacy translation; never enable array3 specialization |
| `duplicate_marker` | Add a second start or end marker | Reject ambiguous marker set |
| `wrong_source_place` | Ref points at another local, field, or projection | Reject source place mismatch |
| `wrong_element_or_length` | Use another element type or array length | Reject; no array interpretation widening |
| `shared_reference` | Ref is shared rather than mutable | Reject |
| `array_to_pointer` | Replace Unsize with ArrayToPointer | Reject |
| `raw_pointer_route` | Produce the slice pointer through a raw-pointer cast | Reject |
| `receiver_mismatch` | Call receiver is not the unique Unsize result | Reject |
| `extra_reference_use` | Copy/store/return either reference temporary elsewhere | Reject; no escape or extra use |
| `wrong_result_local` | `as_mut_ptr` destination is not source binder `begin` | Reject |
| `malformed_protocol` | Change command order, omit owner conversion, borrow/end a different P, or omit dead-capability disposal | Reject before selecting special array ownership |
| `missing_callee_projection` | No attached complete actual std callee body | Reject; never call the std name as a presumed verified callee |
| `unsupported_callee_projection` | Missing body, nonempty unsupported/unavailable reason, count mismatch, branch, call, load/store, Ref creation, or raw-pointer-to-Ref step | Reject |
| `helper_body_mismatch` | Checked helper has different signature, local/step counts, cast kinds, typed cast edges, or output provenance | Reject before redirecting the call |
| `generic_binding_mismatch` | Actual std descriptor does not bind exactly `T = u64` | Reject |
| `unwind_continue` | Method call has `UnwindAction::Continue` | Keep action; restore slice borrow, run post epilogue outside strict scope, convert physical array, then unwind |
| `unwind_cleanup` | Method call has `UnwindAction::Cleanup(bb)` | Keep cleanup target; run checked epilogue, then jump to the same cleanup block |
| `insert_tail_unwind` | Later insert-tail call unwinds after adapter cleanup | Preserve existing R19 normal/unwind cleanup behavior |

No fixture claims proof credit. The method-outcome controls are checked through
the original MIR action and emitted recovery structure; Cloud evidence is still
required for proof acceptance.
