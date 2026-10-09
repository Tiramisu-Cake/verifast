# Checkpoint: независимый review ManuallyDrop::new

2026-10-09. Начало первого tool-интервала14:37:10UTC (первое показание часов
14:37:14UTC); основное окно до15:37:10UTC, предельное завершение до16:07:10UTC.
Scope текущего поручения: две правки постоянных инструкций, независимый static
review одного CFG-патча, локальный кандидат/tests, план Cloud и публикация пакета
в `Tiramisu-Cake/verify-rust-std`, `review/verifast`. Сборки не разрешены.
Сессия завершается после публикации; продление и новая фаза не требуются.

## Результат

Verdict **READY_FOR_CLOUD_VALIDATION**. Исходный патч исправляет лишний successor
у точного identity lowering MDnew; сама проверка dead code остаётся включённой.
Общий cleanup, достижимый от реального panicking call, сохраняется. Блокирующих
дефектов исходного изменения на pinned source не найдено. Существующий checker
нужно усилить привязкой unwind к actual caller и новым false-unwind контролем;
refiner unwind TODO не объявляется закрытым.

Подробности: [карточка review](handoffs/manuallydrop-new-cfg.md),
[evidence](reviews/manuallydrop-new-cfg-20261009/EVIDENCE.md),
[Cloud-план](reviews/manuallydrop-new-cfg-20261009/CLOUD-VALIDATION.md),
[черновик PR](reviews/manuallydrop-new-cfg-20261009/PR-DRAFT.md).

## Checkout, версии и происхождение

- Вход в `/root/verifast`: чистое дерево, `challenge8/verifast-maintainer`,
  `d1d533d27fed74758b1462af29af7e17b2d960c9`. Исторический документационный scope
  и полный STATUS сохраняются в этом commit и прежнем опубликованном пакете.
- Отдельный организационный commit двух поправок:
  `324d247cf6a8e0403b59fbe0a02b7bdd6a504417`. Повтор готового tool kit разрешается
  после provenance/digest/regression checks и actual caller integration;
  пересборка/общие регрессии — при конкретной причине. Permanent rules больше
  не привязаны к первому documentation-only запуску.
- Upstream remote: `https://github.com/verifast/verifast.git`; fetched master
  `f76012fb518703b1d98e243ac4f487f16877cfcb`, совпал с базой кандидата.
  Полная локальная история не shallow; замены по targeted history/API search нет.
- Выбранный опубликованный proof/source snapshot:
  `0ecff7ee7e6fd5d88082915252cae5dd2395bf93`, исходный путь
  `research/challenge-8/verifast-manuallydrop-new-cfg-2610.patch`.
  Blob7c4403b143d69b03b24e437fd4320776b51ca619, SHA256
  `593d09405379974ffbc475c2e0b65d648d8a6913f55b765dd0c3bebdc0922781`.
  Не менялся после введения e6c02f22…; совпадает с ориентиром70e5dfa3….
- Неизменённый перенос, без адаптации/нового translator fix:
  `227dc163117e85d89fb1877bfc1e239a0628e5ab`.
- Candidate + финальные консолидированные tests:
  `1435539475fdaa7810bc2bc780fba0514f765f48`,
  `challenge8/manuallydrop-new-cfg-upstream-candidate`, root tree
  `be55d8d934fb10617309a289e0d546ca1aed6ea0`.
  Development history сохранена отдельно; финальный tree равен9209cc9d….
- Собственный worktree `/root/verifast-manuallydrop-review`, ветка
  `challenge8/manuallydrop-new-cfg-review`, development tip
  `9209cc9dfdf9f70df5a2ee9b790dc7a66caf5cca`. Другие tool компоненты не перенесены.
  Organizational commits не входят в candidate ancestry/upstream diff.
- Подготовлен incremental Git bundle с prerequisite точной upstream-базы;
  bundle/manifest, tool diff и tests diff включены в review artifacts.
  Bundle verify и Git-only receive проверили original commit/tree identities;
  Cloud restore/compiler execution NOT_RUN.

## Прочитанные источники

Proof-материалы читались через `git show` exact snapshot S выше (или authorized
API этого SHA), а evidence через неизменяемый artifact O1. Прочитаны S:
`AGENTS.md`, `research/challenge-8/{WORK-POLICY.md,COMPLETION-PLAN.md}`,
`cloud-build/next-select-frame-caller/PHASE.md`, `cloud-build/{README.md,PARALLEL-BUILDS.md}`,
`OVERNIGHT-SELECT-SORT4-26.10.md`, candidate patch, stock/forget/CFG harnesses,
фактические mem sources и относящиеся transport/runner/recipe исходники.
Политика S — d389ff641194364e5eeda4ea4e66bedac4915a79; coordinator docs —
55414a5c8168061ad960d1f36983334e13699a12. Снимки чужих фаз — context, не бюджет
или разрешение этой роли. По VeriFast-base прочитаны upstream README.txt,
src/README.txt, README.Linux.md, tests/rust/README.md, exporter README,
translator/exporter/refiner/console и тестовый формат.

Proof-worktrees при входе: main HEADf6c1318669f9a9b019dd67d46f345c43e39faa90,
select HEAD0ecff7ee…; позднее remote merge продвинулся до8933d472….
Активные агенты продолжали менять собственные files/ledgers; они сохранены,
незакоммиченные изменения не читались как source или утверждённое evidence.
Наша публикация использует только собственные service refs и Git plumbing,
не меняя proof index, checkout, main, coordinator, ledgers или consumer pins.

## Проверки и NOT_RUN

- Static review main + независимый CFG explorer; evidence explorer прочитал
  существенные оригинальные логи, AST/MIR. Новый исходный патч не исправлялся.
- Authorized GitHub API предоставил O1 run37698481357, job113055959913,
  artifact11517185187. ZIP digest0cd026a6… сверён с API, 650 file hashes сохранены;
  66 source/MIR comparisons stock/candidate совпали. Saved acceptance говорит
  accepted=true только об историческом экспериментальном stock+CFG profile.
- Непосредственно наблюдались stock forget dead-code отказ после normal/leak,
  candidate forget exit0, сохранённый shared unwind через cleanup3,
  intended ordinary false-unwind и contradictory-pre отказы. Это чтение evidence,
  не лично воспроизведённые PASS и не новый replay-классификатор.
- Static diff/границы/links, unchanged patch/transplant code hashes, Git bundle
  verification/receive и artifact inventories проверены без proof execution.
- Новые пять Rust fixtures, baseline/candidate build, VeriFast, rustc, upstream
  suite, actual consumer integration, binary/tool delivery и принятие pin —
  **NOT_RUN**. Cloud бюджет0, submissions0; роль не зарегистрирована.
  Ни статусы чужих proofs, ни theorem coverage не менялись.

## Публикация и следующий шаг

Разрешён только канал review-пакетов: новый каталог
`research/verifast-review/<полный-SHA-этого-checkpoint>/` поверх актуальной головы
`review/verifast`. Предыдущая публикация15ab65bebe4d61bd197cb5feca4e26fb740eaf7c
и пакетd1d533d… сохраняются. Полные instructions/status, review, исходный патч,
tool diff/bundle/tests, PR draft, Cloud-план и provenance manifest входят в новый
пакет. Фактический publication commit/remote/API hash receipt фиксируется после
создания этого immutable checkpoint, во внешнем receipt и финальном отчёте.
Никаких upstream push/issues/PR/fork, main merge или pin adoption не разрешено.

Одно следующее задание: отдельно разрешить реализацию и служебные проверки
`verifast-mdnew-cfg` lane доставки incremental tool bundle с original Git
identities. Dispatcher/роль/phase/budget подключаются только в новом поручении;
до этого сборки не запускаются. Текущая сессия после публикации закрывается.
