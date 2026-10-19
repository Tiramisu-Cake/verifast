# VeriFast maintainer — текущее задание

## Задание

- **ID:** `verifast-fork-sync-2026-10-20-r1`; **статус:** READY, работа ещё не начата.
- **Owner:** `verifast`.
- **Основной worktree:** `/root/verifast`; стартовая branch `infra/maintainer-coordinator-v3-20261012`. Если HEAD продвинулся после документационного checkpoint `d426323cc8824bf85af3cc0a2c7eda03daf7a44c`, установи diff, не откатывай его.
- **Целевой форк пользователя:** `https://github.com/Tiramisu-Cake/verifast.git`; upstream `https://github.com/verifast/verifast.git`. На момент выдачи форк существует, parent=verifast/verifast, default branch=master, доступ ADMIN.
- **Сессия:**120 минут основной работы от фактического T0 + до30 минут завершения. **Google Cloud budget0; GitHub Actions CI для VeriFast явно разрешён владельцем.** Синхронизация и CI на форке — без регистрации GCP phase/ledger. Локальная компиляция/proof execution по-прежнему запрещены; исторические счета не менять.

### Цель и прямое разрешение

**Синхронизировать собственную работу maintainer с новым форком, сохранить наработки и пройти существующий GitHub Actions CI на точном head готового ManuallyDrop candidate.** Сделать понятную карту веток и внешнюю копию готовых наработок, сохранив commits, tests, review/evidence bindings, dirty source и прежние refs. Разрешены инвентаризация, резервные Git refs/bundles, настройка remotes/tracking в своих репозиториях, fetch и обычный push собственных выбранных веток в Tiramisu-Cake/verifast.

Это прямое разрешение владельца на публикацию **собственных веток в его существующем форке**, включая unchanged ManuallyDrop candidate. Прежние запреты публиковать head branch до появления форка снимаются в этой узкой области. Upstream PR/draft/issues/comments/messages, upstream push, releases и consumer pin acceptance не поручены. Роль остаётся [обработкой готовых патчей](/root/verify-rust-std-evidence-brief/research/challenge-8/VERIFAST-ROLE.md); новое proof/model исследование не начинать.

Прочитай `AGENTS.md`, [WORKFLOW](WORKFLOW.md), [STATUS](STATUS.md) и актуальную часть [approval package](reviews/manuallydrop-new-approval-20261009/REVIEW.md). Собственный итог пиши в одном разделе ниже. Не перечитывай все старые proof checkpoints и логи.

### Известная исходная картина

- `/root/verifast`: общий Git repository с множеством worktrees; сейчас только remote upstream→verifast/verifast. **Remotes/config у этих worktrees общие.** Менять их адресно, сохраняя официальный upstream; переключать/переименовывать чужие checkout/branches нельзя.
- `/root/verifast-mdnew-final` — отдельный clone, не worktree общего repository; origin→локальный `/root/verifast`. Branch `upstream/manuallydrop-new-final-20261009`, чистый tested head **`bf63b7dff2e053eea8541996d856fac4be11f6f1`**, base **`0a83dba42db7ce0b445034ece5298afe980e57dc`**, tree **`687ae7dab447c94c4b87362d3d880d959c89e3de`**. Это основная готовая техническая работа maintainer.
- Старые `/root/verifast-manuallydrop-review`, `/root/verifast-mdnew-pr`, `/root/verifast-mdnew-validation` и их branches — части истории подготовки; сохранять связи с финальным кандидатом, не выбирать старый head вместо final.
- `/root/verifast-merge-actual-glue`, branch `merge/actual-glue-instance-20261011`, **принадлежит активному Merge-агенту**. Его новый tool head при проверке был `a42d50becbc84a45e33a58269358eee105f1fdcb`, он может продвинуться. Другие merge/select worktrees и detached heads также не объявлять своими по имени каталога. Только read-only Git metadata для инвентаризации; не менять их файлы/index/HEAD/pins, не публиковать их ветки и не присваивать ownership.
- `ManuallyDrop` PR body SHA **`c1b21d031078e12bfacce8301aee7ec9e9f552e97e4542de2d3cf96c9febb10c`**, title `[Rust] Keep ManuallyDrop::new identity successors consistent with the CFG`. Ранее Linux suite PASS относится к exact candidate/tree, не к сегодняшнему upstream. Новый Actions CI проверяет точный candidate отдельно от прежнего Linux Cloud receipt; Git-синхронизация сама по себе proof credit не создаёт.

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

### 3. Публикация и разрешённый GitHub Actions CI

**Обновление владельца 2026-10-20:** для owner `verifast` GitHub Actions разрешён. Прежнее указание временно отключать Actions ради всех push отменено; не выключай CI. Область — существующие workflows готовых инструментальных патчей в **Tiramisu-Cake/verifast**. Select/Merge продолжают свои Cloud lanes; GCP budget этой сессии0. Самостоятельный запуск на официальном upstream, создание upstream PR/draft, releases и новые hosted/self-hosted runners не поручены.

В форке уже есть `.github/workflows/build.yml` и `gh-pages.yml`; repository Actions enabled=true, но API workflows при проверке ещё не перечислял зарегистрированные workflows. Подтверди активацию/регистрацию существующего CI после публикации, при необходимости включи штатные workflows средствами fork settings/API. Не считай отсутствие запуска PASS. Не меняй candidate/workflow bytes, не ослабляй jobs/checks, не добавляй skip-ci в технический head ради зелёного результата. Прочие permissions/IAM/secrets и официальный upstream не менять. Master/tags/releases по-прежнему не публиковать; gh-pages не является целевым CI.

Push выполняй явно в **Tiramisu-Cake/verifast**, с конкретными source/destination refs, без force/mirror/all/tags. Для каждой published branch сверь полный remote SHA через Git и GitHub API; одного exit0 или tracking ref недостаточно. Remote divergence сохранять разными refs. Tracking менять только у своих canonical branches.

**Целевой запуск:** existing `CI` на branch `fix/manuallydrop-new-cfg` и head **bf63b7dff2e053eea8541996d856fac4be11f6f1**, с тем же tree/base/code/tests. Push должен запустить имеющийся workflow; отдельный workflow_dispatch не нужен, если его нет в исходном YAML. Свяжи run ID/URL/event/attempt/head SHA/workflow revision. Мониторь этот запуск до terminal state в рабочем окне. Не делай массовый re-run; повтор failed jobs допустим при установленном временном infra failure. Лишний дублирующий собственный run можно отменить по точно установленным ID/head/branch; чужие runs не отменять.

Успех означает прохождение всех применимых проверочных jobs существующего workflow: Ubuntu22/24 (включая Rocq mode), macOS, Windows, aarch64 check и flake-check, согласно YAML именно этого head. Release/upload jobs, ограниченные официальным repo/event, могут штатно быть skipped — перечисли их отдельно; skipped test job не превращай в проверенный PASS. Build script → make nightly → release_core включает build/test; сохрани привязку к конкретным jobs/условиям. Перед передачей upstream-пакета наша цель — зелёный CI форка на точном head. Это наша readiness-проверка; наличие обязательной upstream branch protection не установлено. Upstream pull_request CI при будущей разрешённой подаче проверит свой event/merge context отдельно.

**Компактное evidence Actions:** используй API/check-runs/job/step summaries/annotations и короткий отчёт с head/run/job conclusions, skips и измеренной duration. Actions run ID — не GCP Build UUID: не передавай его в smallsort-brief. Для GCP прежний Brief workflow сохраняется. Полные Actions/verifier log archives не скачивай/не выводи; при отказе сначала адресные annotations/summary, неизвестную причину оставь UNKNOWN. Новый CI-сервис/collector не внедрять. Если CI обнаружит проблему code/dependencies/workflow, сохрани конкретный fail/этап и предложение; не переписывай tested candidate под новым именем так, будто он прошёл прежние проверки.

Новый fork/head repository и CI не означают создание upstream PR/его принятие. Проверяй неизменность PR body/title и предыдущих Build/review bindings; historical receipts/verdicts не переписывать.

### 4. Документация и завершение

Обнови компактный STATUS текущим расположением форка/собственных branches и ссылкой на manifest; прежний MDnew status/evidence сохрани как историю. Исправь текущие operational инструкции, утверждающие отсутствие форка, не переписывая immutable review snapshots как будто форк существовал раньше. Если remote metadata PR-пакета устарела, вынеси актуальный head repository/branch/SHA в новый manifest; PR body/code/test bytes и старые approvals сохраняются.

На выходе должно быть ясно: где рабочая docs branch и финальная technical branch, что опубликовано на GitHub, что осталось локальным и почему, где recovery bundles и какие refs больше не являются актуальными. Все значимые исходные worktrees/heads/dirty source сохранены; активные proof-агенты продолжают на прежних checkout/pins.

T0/main/absolute запиши при фактическом начале. После T+120 не начинай новую миграцию/группу веток/новый эксперимент CI; до T+150 заверши начатые публикации, мониторинг/учёт/отчёт. Если существующий Actions run ещё выполняется, запиши точный pending run ID/статус, не объявляй PASS и не сбрасывай T0; дальнейшее серверное выполнение не означает фоновую работу агента. Не заполняй окно искусственно, если цель выполнена. GCP Cloud0; Actions run durations учитывай отдельно от GCP seconds, потолок3600 proof-агентов сюда не переносить. Локальная компиляция/actual verification и full-log чтение запрещены. Optional bounded helpers — только GPT-6 Luna HIGH, fork_turns=none, без вложенной делегации; не использовать старое указание WORKFLOW об автоматической эскалации модели.

## Отчёт агента

Один перезаписываемый отчёт, без повторных дневников. Перед следующим заданием координатор архивирует завершённый CURRENT-TASK в `task-history/<ID>.md` и заменяет задание. Подробности — manifest/ссылками, не огромным списком refs в чате.

- **Статус / T0/main/absolute/end:** NOT_STARTED / —.
- **Исходные repositories/HEAD и backups:** —; bundle verification/restore checks —.
- **Fork/remotes и canonical branches:** old branch/SHA → new branch/SHA → remote SHA/проверка —.
- **Сохранность MDnew:** head/base/tree/PR body/title; code/tests unchanged —.
- **Другие собственные наработки / foreign active worktrees / UNKNOWN owners:** —.
- **Actions CI:** workflow/run URL/ID/event/head/attempt; jobs PASS/FAIL/skipped/pending, причины skips/failure, duration и точные границы —.
- **Docs/manifest checkpoint и опубликованный SHA:** —.
- **Расход:** GCP Cloud0/Builds0; GitHub Actions runs/durations отдельно —; upstream PR/releases/messages0.
- **Что осталось несинхронизированным / готовность CI к upstream-подаче / конкретный следующий шаг:** —.
