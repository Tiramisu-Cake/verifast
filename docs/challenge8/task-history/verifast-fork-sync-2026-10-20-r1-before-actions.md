# VeriFast maintainer — текущее задание

## Задание

- **ID:** `verifast-fork-sync-2026-10-20-r1`; **статус:** READY, работа ещё не начата.
- **Owner:** `verifast`.
- **Основной worktree:** `/root/verifast`; стартовая branch `infra/maintainer-coordinator-v3-20261012`. Если HEAD продвинулся после документационного checkpoint `d426323cc8824bf85af3cc0a2c7eda03daf7a44c`, установи diff, не откатывай его.
- **Целевой форк пользователя:** `https://github.com/Tiramisu-Cake/verifast.git`; upstream `https://github.com/verifast/verifast.git`. На момент выдачи форк существует, parent=verifast/verifast, default branch=master, доступ ADMIN.
- **Сессия:**120 минут основной работы от фактического T0 + до30 минут завершения. **Cloud budget0, CI/компиляция/proof execution не разрешены.** Это организационная Git-задача, без регистрации Cloud phase/ledger и без изменения исторических счетов.

### Цель и прямое разрешение

**Синхронизировать собственную работу maintainer с новым форком, сделать понятную карту веток и внешнюю копию готовых наработок, сохранив commits, tests, review/evidence bindings, dirty source и прежние refs.** Разрешены инвентаризация, резервные Git refs/bundles, настройка remotes/tracking в своих репозиториях, fetch и обычный push собственных выбранных веток в Tiramisu-Cake/verifast.

Это прямое разрешение владельца на публикацию **собственных веток в его существующем форке**, включая unchanged ManuallyDrop candidate. Прежние запреты публиковать head branch до появления форка снимаются в этой узкой области. Upstream PR/draft/issues/comments/messages, upstream push, releases и consumer pin acceptance не поручены. Роль остаётся [обработкой готовых патчей](/root/verify-rust-std-evidence-brief/research/challenge-8/VERIFAST-ROLE.md); новое proof/model исследование не начинать.

Прочитай `AGENTS.md`, [WORKFLOW](WORKFLOW.md), [STATUS](STATUS.md) и актуальную часть [approval package](reviews/manuallydrop-new-approval-20261009/REVIEW.md). Собственный итог пиши в одном разделе ниже. Не перечитывай все старые proof checkpoints и логи.

### Известная исходная картина

- `/root/verifast`: общий Git repository с множеством worktrees; сейчас только remote upstream→verifast/verifast. **Remotes/config у этих worktrees общие.** Менять их адресно, сохраняя официальный upstream; переключать/переименовывать чужие checkout/branches нельзя.
- `/root/verifast-mdnew-final` — отдельный clone, не worktree общего repository; origin→локальный `/root/verifast`. Branch `upstream/manuallydrop-new-final-20261009`, чистый tested head **`bf63b7dff2e053eea8541996d856fac4be11f6f1`**, base **`0a83dba42db7ce0b445034ece5298afe980e57dc`**, tree **`687ae7dab447c94c4b87362d3d880d959c89e3de`**. Это основная готовая техническая работа maintainer.
- Старые `/root/verifast-manuallydrop-review`, `/root/verifast-mdnew-pr`, `/root/verifast-mdnew-validation` и их branches — части истории подготовки; сохранять связи с финальным кандидатом, не выбирать старый head вместо final.
- `/root/verifast-merge-actual-glue`, branch `merge/actual-glue-instance-20261011`, **принадлежит активному Merge-агенту**. Его новый tool head при проверке был `a42d50becbc84a45e33a58269358eee105f1fdcb`, он может продвинуться. Другие merge/select worktrees и detached heads также не объявлять своими по имени каталога. Только read-only Git metadata для инвентаризации; не менять их файлы/index/HEAD/pins, не публиковать их ветки и не присваивать ownership.
- `ManuallyDrop` PR body SHA **`c1b21d031078e12bfacce8301aee7ec9e9f552e97e4542de2d3cf96c9febb10c`**, title `[Rust] Keep ManuallyDrop::new identity successors consistent with the CFG`. Ранее Linux suite PASS относится к exact candidate/tree, не к сегодняшнему upstream. Синхронизация Git не требует повторной компиляции и не создаёт нового proof credit.

### 1. Сначала инвентаризация и проверяемая сохранность

В своём организационном каталоге подготовь компактный `FORK-SYNC-MANIFEST` с исходной и итоговой картой: repository/common-dir, worktree, branch или detached HEAD, полный SHA/tree, владелец/назначение, dirty/untracked source, remote/tracking и действие. Реестр веток получай Git metadata, не списком всех файлов/логов. Для неизвестного владельца честно UNKNOWN; такое дерево оставить без вмешательства.

Сними исходные refs/remotes/config и HEAD всех relevant worktrees, включая отдельный final clone. До переименований/переключений/публикаций сохрани собственные ветки/tags и нужные detached commits в локальные backup refs и verified Git bundle для каждого независимого repository. Сохрани собственный dirty source/index binary diff и необходимые untracked исходники/patches/specs/docs отдельно с путями/hashes; не делай auto-stash/reset/clean. Чужие активные dirty деревья оставить на месте, не копировать/читать raw evidence. Проверяй только наличие/метаданные архивных evidence, не открывай их содержимое.

Bundle должен действительно содержать исходные значимые commits/trees и проверяться `git bundle verify`; для важных heads проверь доступность объектов в изолированном Git restore/inspection без compiler/source extraction. Укажи абсолютные пути/hashes backup и способ восстановления. Не делай git gc/prune/reflog expire, удаление refs/worktrees или массовое mirror/all push. Резервная копия на VPS — локальный recovery, публикация выбранных refs в форк — отдельная внешняя копия.

### 2. Remotes и понятные ветки

- В общем `/root/verifast` сохрани upstream=официальный repository, добавь origin=форк пользователя (если origin появился, сначала проверь URL/ownership, не затирай его). Fetch без prune; не менять global Git config/identity.
- Для отдельного final clone сохрани действующее локальное соединение с `/root/verifast` под ясным именем local-source; origin назначь форку и upstream официальному repository. Сначала snapshot config, не терять доступ к исходным refs/objects. Не применять изменение remotes повторно к каждому worktree одного common-dir.
- Используй собственную организационную branch **`maintenance/fork-sync-20261020`** от актуального собственного docs HEAD и техническую canonical branch **`fix/manuallydrop-new-cfg`** на exact tested bf63b7df. Если такое имя уже занято другим head, не перезаписывай: выбери уникальное имя и запиши mapping/conflict. Existing old branches сохранить с прежними SHA как историю; новые canonical aliases/tracking и manifest должны снять путаницу. Не переименовывай активные checked-out ветки других агентов.
- Для остальных собственных наработок укажи статусы: ready candidate, validation/review history, organizational, experimental или inactive legacy. Подтверждай ownership по source/handoff/history, а не prefix имени. Публикуй только выбранные подтверждённо собственные refs; неизвестные/чужие/непредназначенные для GitHub данные оставь локально с ясной пометкой.
- Сверь master/upstream/fork ahead/behind и зафиксируй baseline. В этой задаче не rebase/amend/cherry-pick/merge tested candidate, не продвигай fork master/tags и не обновляй чужие experimental profiles. Когда понадобится свежая upstream base, это отдельный кандидат со своей проверкой. Branch cleanup сейчас означает canonical refs, tracking и классификацию с сохранением прежней истории; удаление отложено.

### 3. Публикация без запуска CI

**Конкретная проверенная зависимость:** в форке Actions enabled=true, а candidate `.github/workflows/build.yml` запускается на push без ограничения branch. Поэтому обычный push может запустить тяжёлый CI. Эта сессия разрешает **временное отключение Actions только в Tiramisu-Cake/verifast для безопасной публикации refs**, с сохранением/восстановлением исходной настройки после последнего push. Это узкое исключение для Git-синхронизации, не разрешение workflow dispatch/сборок/изменения upstream или GCP.

Сначала перечитай фактическую настройку/существующие workflow triggers в целевом форке, сохрани исходное состояние и временно выключи Actions средствами repository settings/API; проверь выключение до первого push. Сами `.github/workflows` и candidate commits не изменять, skip-ci commit не добавлять. Прочие permissions/IAM/secrets не трогать. После всех выбранных публикаций/отчётного push восстанови исходное Actions состояние и проверь его; не создавай новый push после восстановления. Фактическое финальное восстановление подтверди в конечном ответе. Если состояние/права не позволяют выполнить этот безопасный порядок, сохрани готовые bundles/точный blocker без запуска CI и без обхода отказа.

Push выполняй явно в **Tiramisu-Cake/verifast**, с конкретными source/destination refs, без force/mirror/all/tags. Для каждой published branch сверь полный remote SHA через Git и GitHub API; одного exit0 или локального tracking ref недостаточно. При remote divergence сохрани обе истории под разными refs, не force-push. Назначь tracking собственным canonical branches; не перенастраивай tracking чужих веток. Проверь, что новые Actions runs из-за публикации не появились; ничего не dispatch/re-run. Не отменяй чужие существовавшие runs.

Для MDnew готовая ветка на форке должна содержать **те же bf63b7df/tree/base/code/tests**, без организационных commits в техническом PR candidate. Проверь SHA PR body/title и связи с прежними Build/review. Наличие новой head branch не означает создание upstream PR или его принятие; historical receipts и прежние verdicts остаются прежними.

### 4. Документация и завершение

Обнови компактный STATUS текущим расположением форка/собственных branches и ссылкой на manifest; прежний MDnew status/evidence сохрани как историю. Исправь текущие operational инструкции, утверждающие отсутствие форка, не переписывая immutable review snapshots как будто форк существовал раньше. Если remote metadata PR-пакета устарела, вынеси актуальный head repository/branch/SHA в новый manifest; PR body/code/test bytes и старые approvals сохраняются.

На выходе должно быть ясно: где рабочая docs branch и финальная technical branch, что опубликовано на GitHub, что осталось локальным и почему, где recovery bundles и какие refs больше не являются актуальными. Все значимые исходные worktrees/heads/dirty source сохранены; активные proof-агенты продолжают на прежних checkout/pins.

T0/main/absolute запиши при фактическом начале. После T+120 не начинай новую миграцию/группу веток; до T+150 заверши начатые публикации, восстановление временной настройки, проверки/учёт/отчёт. Не заполняй окно искусственно, если цель выполнена. Cloud0, локальная компиляция/actual verification и full-log чтение не нужны. Optional bounded helpers — только GPT-6 Luna HIGH, fork_turns=none, без вложенной делегации; не использовать старое указание WORKFLOW об автоматической эскалации модели.

## Отчёт агента

Один перезаписываемый отчёт, без повторных дневников. Перед следующим заданием координатор архивирует завершённый CURRENT-TASK в `task-history/<ID>.md` и заменяет задание. Подробности — manifest/ссылками, не огромным списком refs в чате.

- **Статус / T0/main/absolute/end:** NOT_STARTED / —.
- **Исходные repositories/HEAD и backups:** —; bundle verification/restore checks —.
- **Fork/remotes и canonical branches:** old branch/SHA → new branch/SHA → remote SHA/проверка —.
- **Сохранность MDnew:** head/base/tree/PR body/title; code/tests unchanged —.
- **Другие собственные наработки / foreign active worktrees / UNKNOWN owners:** —.
- **Actions:** исходная настройка, отключение на время push, новые runs, порядок финального восстановления —; последнее состояние подтвердить также в конечном ответе после final push.
- **Docs/manifest checkpoint и опубликованный SHA:** —.
- **Расход:** Cloud0/Builds0; внешние PR/releases/messages0.
- **Что осталось несинхронизированным и конкретный следующий шаг:** —.
