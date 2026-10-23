# VeriFast maintainer — консолидация экспериментальной tool-цепочки SmallSort

## Задание

- **ID:** `verifast-toolchain-consolidation-2026-10-24-r3`; **статус:** READY, сессия ещё не начата. Предыдущее задание (`verifast-windows-ci-ready-patch-2026-10-20-r2`, выполнено) сохранено в [архиве](task-history/verifast-windows-ci-ready-patch-2026-10-20-r2.md).
- **Owner:** `verifast`. **Runtime:** Codex (independent review — GPT-6 Luna HIGH, `fork_turns="none"`, без вложенной делегации).
- **Docs worktree:** `/root/verifast`, branch `maintenance/fork-sync-20261020`, исходный checkpoint **`92fb66c591ee7f0af6965e9ec6c7090570588349`**. Более новые commits проверь, не откатывай.
- **Technical worktree:** создай собственный, например `/root/verifast-integration-20261024`, на новой ветке `integration/smallsort-toolchain-20261024` форка `Tiramisu-Cake/verifast` (upstream `verifast/verifast`). Remotes common worktrees общие; повторная миграция не требуется. Worktrees и ветки proof-агентов (`/root/verifast-select-sort4-c2-bind-20261010`, `/root/verifast-merge-actual-glue`, `/root/verifast-network-n13`, `/root/verifast-mdnew-final`) — только чтение.
- **Окно (разовая практика по решению владельца 23.10, [PROGRESS-REVIEW §9](/root/verify-rust-std-evidence-brief/research/challenge-8/PROGRESS-REVIEW.md)):** время сессии не ограничено; T0 при фактическом начале; сессия закрывается по достигнутой цели, конкретному внешнему/семантическому препятствию или после проверки всех независимых полезных шагов. Не заполнять время формальной активностью. **GitHub Actions разрешён; GCP budget 0 / Builds 0.** Число CI-итераций отдельно не ограничено; runs/attempts/durations учитывать отдельно. VPS compilation/proof execution запрещены.
- Примерно каждые 2 часа активной работы — короткий progress без ожидания ответа. Владелец вопросов в окне не отвечает: спорные моменты решай сам, запиши альтернативы и выбор в checkpoint; решения, зарезервированные за владельцем (новые trusted semantics, ослабление checks, upstream-публикация), оформляй как открытый вопрос и переходи к следующему шагу.

### Цель

**Собрать опубликованные экспериментальные tool-изменения Select и Merge вместе с ManuallyDrop-патчем в одну integration-ветку форка с полной CI-матрицей, отчётом о совместимости и trust ledger.** Это обработка уже опубликованных патчей (review, регрессии, совместимость/интеграция, подготовка upstream-пакета), не исследование proof-blockers. Причина: tool-цепочка Merge ушла от stock 26.09 примерно на 90 commits, Select накладывает proof-time overlays translator'а, Network сидит на stock; без консолидации W10 («итоговый профиль и воспроизводимость») станет обрывом.

### Входы (точные identities на 2026-10-23)

| Источник | Где | Что |
| --- | --- | --- |
| Stock baseline | tag `26.09` = `809de4596839b739dd999f9e462242c835e3af46` | Профиль Network, без патчей |
| Upstream base Select/Merge | `f76012fb518703b1d98e243ac4f487f16877cfcb` (upstream master, #1033) | Tool pin Select; база цепочки Merge |
| Merge fork branches | `merge/actual-glue-instance-20261011` (head `e1ee4415…`, содержит исполненный tuple `578120769161e217e53bd569bafdccbd4b2e020e`, 58 commits над f760); `merge/r22-translator-fixtures-20261023` `65f0bb35…`; `merge/r22-complete-region-fixtures-20261023` `6755ae50…`; `merge/r22-owned-nll-capture-20261023` `fc0208d4…` (admission NEEDS_FIX, default-off); `merge/r22-owned-nll-borrow-sites-20261023` `0f4e336b…` (not root-admitted) | Translator/exporter/decoder изменения Merge; статусы по `cloud-build/origin-layout/R22-CLOSEOUT-20261023.json` и `TOOL-CHAIN.md` (появится в Merge R23) в `/root/verify-rust-std-merge-origin` |
| Select proof-time overlays | `/root/verify-rust-std-select-night` @ `505aea0d…`: `research/challenge-8/overnight-assume-actual/*.patch`, `research/challenge-8/task-history/select-callee-r23/ghost-cleanup-successor-fractional.patch` (SHA-256 `03f91fb5…`), pins `task-history/select-callee-r23/PROOF-PINS.json` (translator `2d6f1950…`), `GHOST-CFG-PROOF-PINS.json` (base `cadaa80a…` → final `103a34af…`) | Патчи поверх f760, применяются в Cloud при proof; точную цепочку Select R24 опубликует в `task-history/select-callee-r24/TOOL-OVERLAYS.md` — до появления читай pins и patch-файлы |
| ManuallyDrop | `fix/manuallydrop-new-cfg-windows-20261020` `ac6a63d5…`, base `0a83dba4…`, upstream draft PR 1046 | Готовый reviewed патч с зелёным CI |

Uncommitted правки в `/root/verifast-select-sort4-c2-bind-20261010` (lib.rsspec, rust_parser.ml, vf_mir_translator.ml, verifast.ml) — чужие рабочие файлы: не копировать и не трогать; источником служат только committed patch-файлы и pins.

### Результаты

1. **Handoff card** `handoffs/smallsort-toolchain-consolidation-20261024.md` по полям WORKFLOW (ID, источники с full SHA, до/после, review, регрессии, статус каждого consumer).
2. **Integration-ветка** `integration/smallsort-toolchain-20261024` в форке: база `f76012fb` (проверь ancestry относительно `0a83dba4` и tag 26.09, запиши); затем Merge chain (`578…` блоком, r22-ветки отдельными блоками с их статусами); затем Select overlays как commits в pin-порядке, каждый с patch SHA-256 и фактическим hash translator после применения (сверить с `2d6f1950`/`cadaa80a`/`103a34af`; при несовпадении зафиксировать точное расхождение, не подгонять); затем ManuallyDrop `ac6a63d5`, если не входит. Конфликты не разрешать «на глаз»: конфликтующий hunk — finding автору, кандидат оставить в отдельной ветке и в отчёте.
3. **CI форка на exact integration head:** полная существующая матрица (Ubuntu22/24 Rocq, macOS, Windows, aarch64, flake-check) и Rust test suite; для локализации провалов допустимы контрольные runs отдельных слоёв (f760 + только Merge, f760 + только Select overlays). Checks не ослаблять, expected outputs не подменять; skipped не считать PASS. Для непонятного провала — bounded первый содержательный фрагмент лога по правилам прошлого задания (annotations/check/job summaries → GET range ≤12000 байт/20 строк; `gh run view --log*` и полные архивы запрещены).
4. **Отчёт** `toolchain-20261024/COMPATIBILITY.md`: пересечения hunks Select↔Merge; какие семантические правила каждый слой добавляет и чем они gated (profile/env/flag/глобально); **trust ledger** (каждый новый predicate/lemma/rule/certificate-check с source commit, owner, статусом experimental/admitted); upstreamable subset (portability/parser/decoder fixes) против experimental; рекомендация единой базы для W10. Findings авторам — `toolchain-20261024/FINDINGS-select.md`, `FINDINGS-merge.md`; их worktrees, pins, ledgers не редактировать.
5. **Минимальные адаптации** при интеграции (build wiring, registration, portability) — отдельными commits с rationale/controls и независимым Luna HIGH review до CI; семантику патчей не менять, новых lowering/model/axioms не разрабатывать, новые proof-blockers не исследовать (VERIFAST-ROLE).

### Границы

Green CI — regression readiness, не proof credit, не consumer pin и не upstream acceptance. Не создавать upstream PR/draft/issues/comments/messages/releases; PR 1046 не трогать и не пинговать. Fork `master`/tags, GCP coordinator/IAM, чужие worktrees/pins/ledgers не менять. Без PAT/новых secrets; credentials и полный environment не печатать. Commit/push только собственных веток форка; старые heads не переписывать. Docs checkpoint коммитить в текущую docs-ветку с `[skip ci]` (только для docs-only commits).

В конце обнови компактный STATUS, handoff card и отчёты; ниже один перезаписываемый отчёт. GCP 0; Actions runs/attempts/wall/job durations отдельно; wall-clock не равен active agent time.

## Отчёт агента

- **Статус / T0 / end:** READY, сессия не начата.
- **План / integration head / CI / отчёт / findings / blocker / следующий шаг:** заполняется агентом.
