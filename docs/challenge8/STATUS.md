# Checkpoint: подготовка роли verifast

2026-10-09, обследование с 14:11 UTC. Разрешённый scope: только постоянные
инструкции и документация. [AGENTS.md](../../AGENTS.md), [WORKFLOW.md](WORKFLOW.md).
Это снимок первого запуска, а не текущее состояние работающих proof-агентов.

## Checkout и доступ

- VeriFast: `/root/verifast`, единственный зарегистрированный worktree;
  при входе чистый, ветка `research/challenge-8`, HEAD
  `f76012fb518703b1d98e243ac4f487f16877cfcb` (upstream base первого запуска).
- Для документации создана локальная ветка `challenge8/verifast-maintainer`
  от этого HEAD. Документационный commit определяется через
  `git log -1 --format=%H -- docs/challenge8/STATUS.md`; SHA сообщается в отчёте.
- Единственный remote VeriFast: `upstream`, fetch/push URL
  `https://github.com/verifast/verifast.git`. Fork/origin не настроены.
- Proof-проект: `/root/verify-rust-std`, общий Git dir
  `/root/verify-rust-std/.git`; `origin` (fetch/push) —
  `https://github.com/Tiramisu-Cake/verify-rust-std.git`.
- Аккаунт владельца ограничен по сообщению владельца. Доступ к GitHub/Cloud
  в этом запуске не проверялся; fetch/push/внешних сообщений не было.
  Локальные SHA не объявляются опубликованными или доступными Cloud.

Найденные и проверенные read-only Git-командами proof-worktrees:

| Путь | Ветка (либо detached) | HEAD при обследовании |
| --- | --- | --- |
| `/root/verify-rust-std` | `overnight/merge-26.10` | `d793eaa25f5cb4de92cda44ba9fc94ea1162d296` |
| `/root/verify-rust-std-select-night` | `research/night-select-sort4-cloud-2026-10-09` | `0ecff7ee7e6fd5d88082915252cae5dd2395bf93` |
| `/root/verify-rust-std-merge` | `challenge-8/merge` | `8444589f486e82f23c910bcc918cee1e4681b7ee` |
| `/root/verify-rust-std-networks` | `challenge-8/networks` | `a9c8913317cbc6d17a8100a8237d50f2356cb5f3` |
| `/dev/shm/c8-preserved-sort4-night-workflow` | detached | `4771dd9894b28312edf40e16d6398628beaf498f` |
| `/dev/shm/c8-stock-2610` | `research/stock-26.10-baseline` | `80d9c0c318f71f49c3531883f7953883cb04c2f4` |
| `/dev/shm/c8-sync-main` | `sync/upstream-cd371-main` | `af1ef9d0747b2f77febe2c3be7d7e6b65d9cdb27` |
| `/dev/shm/c8-sync-merge` | `sync/upstream-cd371-merge` | `b0af5613e18699c877ef9b7a7ea27b00c7827dda` |
| `/dev/shm/c8-sync-research` | `sync/upstream-cd371-research` | `a06cfb9d9dd95cf5a8875bd5d2f9bd85df47fadd` |
| `/tmp/challenge8-workflow-default` | detached | `3d8c8c082a69dbb66c4ab566892e6be71d87a86d` |
| `/tmp/sort4-constructor-workflow` | detached | `196121c11fee754327692a6aae7c97670d809c74` |

При входе в основном proof-tree изменён
`research/challenge-8/cloud-build/next-merge-drop-caller/BUDGET.json`; в select-tree
был untracked `next-select-frame-caller/FIRST-PREFLIGHT.json`, при чтении агент
также наблюдал изменённый `BUDGET.json` этой фазы. Это активные чужие деревья;
содержимое этих незакоммиченных изменений не читалось и не менялось.
Остальные перечисленные деревья при проверке были чистыми. Новые clones/worktrees
не создавались; чужие ветки/index/remotes/pins/ledgers не менялись.

## Прочитанные версии

Все proof-материалы читались через `git show <full-sha>:<path>` из двух точных
деревьев выше: **M** = `d793eaa25f5cb4de92cda44ba9fc94ea1162d296`,
**S** = `0ecff7ee7e6fd5d88082915252cae5dd2395bf93`.
Пути ниже относительны корню proof-проекта; SHA в правой колонке — последнее
изменение файла в соответствующем дереве, а M/S — версия целиком прочитанного дерева.

| Прочитано | Дерево | Последнее изменение |
| --- | --- | --- |
| `AGENTS.md`, `research/challenge-8/WORK-POLICY.md`, `COMPLETION-PLAN.md` в той же директории | M | `1fcd91eff1507fe0bd0620a23b578edb454f1c3e` |
| Та же тройка | S | `d389ff641194364e5eeda4ea4e66bedac4915a79` |
| `research/challenge-8/merge/NEXT-MERGE-DROP-CALLER-CHECKPOINT-2026-10-09.md` | M | `d793eaa25f5cb4de92cda44ba9fc94ea1162d296` |
| `research/challenge-8/merge/overnight/guard-ownership/insertion-onecell/SEMANTIC-CARD.md` | M | `d793eaa25f5cb4de92cda44ba9fc94ea1162d296` |
| `research/challenge-8/merge/NEXT-MERGE-DROP-CALLER-CLOUD-2026-10-09.md` | M | `731fab682b0ffc262098c0fd5f3876427154311e` |
| `research/challenge-8/cloud-build/next-select-frame-caller/PHASE.md` (нового END-CHECKPOINT в этом дереве ещё нет) | S | `0ecff7ee7e6fd5d88082915252cae5dd2395bf93` |
| `research/challenge-8/cloud-build/afternoon-select-sort4/END-CHECKPOINT-2026-10-09.md` | S | `f398c06b99d706a2bf8fa80e56478fd3cf36b7ed` |
| `research/challenge-8/cloud-build/night-select-sort4/END-CHECKPOINT-2026-10-09.md` | S | `20258b67c17d7e17ae25967488a98060969915a8` |
| `research/challenge-8/cloud-build/README.md`, `PARALLEL-BUILDS.md` в той же директории | M | `c81fd1a517b9ad2b3ecf0b6d6ab3f50b841d5f8c` |
| Те же coordinator docs | S | `55414a5c8168061ad960d1f36983334e13699a12` |

Дополнительно для понимания checkpoint прочитаны committed M
`research/challenge-8/cloud-build/next-merge-drop-caller/{SESSION-STATE.json,BUDGET.json}`
и S `research/challenge-8/cloud-build/next-select-frame-caller/BUDGET.json`.
Различия policy/coordinator docs сопоставлены: обе версии требуют v2 two-slot
admission, а S подробнее закрепляет постоянную Cloud-границу и pinned-object input.
Исторические разрешения фаз не перенесены новой роли.

В VeriFast на `f76012fb518703b1d98e243ac4f487f16877cfcb` прочитаны
`README.md`, `README.txt`, `README.Linux.md`, `src/README.txt`,
`tests/rust/README.md`, `src/rust_frontend/vf_mir_exporter/README.md`.
Существующих `AGENTS.md`/CONTRIBUTING-инструкций для самого VeriFast не найдено;
upstream документы сохранены без изменений. Правила делегирования пользователя
включены в новые инструкции.

## Результат и следующий запуск

Инфраструктура роли `verifast` **ещё не подключена**: нет разрешённой Cloud-фазы,
бюджета, собственного ledger/регистрации. Существующий coordinator не менялся.
Очередь передачи, review и tool release ещё не начаты.

Новых proof results нет. Build, proof execution, полноценные регрессии,
повторная проверка старых результатов и review `ManuallyDrop::new` — **NOT_RUN**.
Инвентаризация патчей и перенос кода/specs/tests не выполнялись. Выполнена только
статическая проверка документации, ссылок и diff перед локальным commit.

В M checkpoint/session-state описывают unresolved Build, тогда как committed
ledger уже отмечает его terminal; семантическая карточка описывает сбой до proof
execution. Это документальное расхождение не было reconciled с Cloud API и не
даёт proof credit. Перед зависимым execution владелец должен сверить текущие
evidence/ledger. Подготовке инструкций и отдельному локальному review оно не мешает.

Рекомендуемое следующее задание: независимое review конкретного candidate
`ManuallyDrop::new` по предоставленному точному SHA и воспроизводимому caller
блокеру, с карточкой передачи и планом минимальных регрессий. Разрешение Cloud
и бюджет для их исполнения оформляются отдельно; это предложение не начинает review.
