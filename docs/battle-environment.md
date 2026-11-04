# Погода, поле и условия сторон: PR 4

Дата: **4 ноября 2026 года**. Задача [#57](https://github.com/SlowBroshka/pokemon_showdown_client/issues/57).
Основа — [контракт механик](battle-mechanics-contract.md) и [эффекты покемонов PR 3](battle-effects.md).

## Подробный план, изложенный до реализации

1. Добавить в BattleState отдельное неизменяемое окружение комнаты/epoch:
   погоду, один terrain, общие условия поля и условия сторон p1/p2.
   Замены, обмороки и приватные запросы не должны сбрасывать окружение.
2. Поддержать Rain Dance, Sunny Day, Sandstorm и Snowscape: начало, замену,
   upkeep и none. Хранить ход начала, последний upkeep и публичный источник,
   не вычислять скрытые таймеры, предметы или эффективные множители.
3. Поддержать Electric/Grassy/Misty/Psychic Terrain, Gravity и
   Trick/Magic/Wonder Room. Terrain заменяется целиком; остальные условия
   сосуществуют и заканчиваются независимо.
4. Поддержать десять условий сторон: Spikes (до 3), Toxic Spikes (до 2),
   Stealth Rock, Sticky Web, Reflect, Light Screen, Aurora Veil, Mist,
   Safeguard, Tailwind. Снятие удаляет все слои; превышение лимита блокирует
   управление без частичного обновления.
5. Атомарно обменивать условия сторон по Court Change, сохраняя слои и
   сведения о начале. Узко принять сопутствующий -activate без второго обмена.
   Perish Song/Teatime fieldactivate записывать как наблюдения, не поля.
6. Сохранить блокировки неизвестных механик и request-only авторизацию.
   Fairy Lock нельзя считать декоративным сообщением: его поддержка отложена.
7. Заменить шесть прежних guard-сценариев положительными промежуточными
   проверками, добавить тесты слоёв, снятия, замены terrain, обмена, истории,
   неизменяемости, изоляции и защиты от повторной отправки выбора.
8. Обновить матрицу и документацию, выполнить format/analyze/full tests,
   опубликовать PR через SlowBroshkas-bot / Primary.

## Проверенные источники

Используется закреплённый Showdown
[`b354a81f11003a03f0dcd1dafd4edc641e6763bd`](https://github.com/smogon/pokemon-showdown/tree/b354a81f11003a03f0dcd1dafd4edc641e6763bd).
Снимок PR 1 не обновлялся. Источники прочитаны из checkout этого SHA.

- [SIM-PROTOCOL](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/sim/SIM-PROTOCOL.md#L420):
  погода/upkeep, fieldstart/end/activate, sidestart/end, swapsideconditions.
- [field.ts](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/sim/field.ts#L129):
  setTerrain заменяет terrain **без отправки конца прежнего**; clearTerrain
  отправляет явный конец. Pseudo-weather хранится независимо.
- [conditions.ts](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/conditions.ts#L480):
  погодные start/upkeep/end, источник способности, скрытая зависимость длительности
  от предмета. Старые Hail и primal weather в реестр Gen9 Random Battle не включены.
- [moves.ts: Court Change](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L3032):
  явный список переносимых условий; все десять поддержанных входят в него.
  После swapsideconditions сервер отправляет отдельное activate.
- [Spikes](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L17496)
  и [Toxic Spikes](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L19745):
  каждый успешный слой сообщает sidestart; на лимите нового сообщения нет.
  Поэтому превышение лимита входным сообщением считается несогласованным состоянием.
- [Fairy Lock](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L5050):
  fieldactivate создаёт реальный эффект duration=2. Он остаётся заблокированным,
  в отличие от сообщения Perish Song и Teatime, чьи последствия приходят отдельно.

## Модель

`BattleState.environment` — `BattleEnvironment`, независимый от BattleRoster.
Копирование BattleState сохраняет окружение, если не передана новая проекция.
Новая комната/epoch получает пустое окружение. Завершение/закрытие/stale сохраняет
последний снимок; последующие события не изменяют его.

| Поле | Представление |
| --- | --- |
| weather | EnvironmentCondition или null |
| terrain | один EnvironmentCondition или null |
| fields | неизменяемая карта Gravity и трёх Rooms |
| p1 / p2 | неизменяемые карты условий каждой стороны |
| activations | последние 50 наблюдений FieldActivation |

`EnvironmentCondition` содержит нормализованный id, startedTurn, layers,
sourceEffect/sourceIdent и lastUpkeepTurn. Это наблюдённые публичные сведения.
`sourceIdent` — текстовая метка, не доказанная личность покемона и не приватный
слот. Уход источника не удаляет эффект и не меняет его метку. Новый слой сохраняет
сведения первого слоя; повторный start однослойного условия обновляет наблюдение.

Не хранятся предполагаемая дата окончания, скрытый предмет, действие погоды
при подавлении способностью, вычисленный урон или легальность приёмов.
Окружение остаётся до соответствующих серверных событий, даже спустя 20 ходов.

## Правила переходов

- Weather start заменяет текущую погоду и её метаданные. Upkeep требует совпадения
  текущего id, сохраняет начало/источник и обновляет только lastUpkeepTurn.
  Повтор upkeep на том же ходу идемпотентен. None очищает погоду.
- Fieldstart terrain заменяет предыдущий terrain. Конец старого/отсутствующего
  terrain не удаляет другой текущий terrain. Концы полей удаляют только свой id.
- Sidestart добавляет слой только для Spikes/Toxic Spikes. Sideend удаляет
  условие целиком и идемпотентен при отсутствии условия. Имя игрока не является
  ключом стороны; p1/p2 сохраняют значение после смены отображаемого имени.
- Swapsideconditions меняет обе карты одновременно. Слои, ход начала и публичный
  источник переходят вместе с условием; погода/terrain/fields не меняются.
  Court Change activate проверяет активного отправителя и не меняет карты.
  При расширении реестра нужно отдельно сверять переносимость новых условий:
  нельзя автоматически переносить любые будущие условия сторон.
- Perish Song/Teatime fieldactivate добавляет ограниченную запись id+turn.
  Не создаёт постоянного поля, не назначает счётчики покемонам и не расходует
  предметы локально. История больше 50 записей обрезается с начала.

Новый декодер обслуживает семь типов окружения и только Court Change из -activate.
Другие activate остаются неизвестными для обработки будущим PR 5. Принимаются
публичные trailing-аннотации `[from] move:/ability:`, `[of] p1/p2` (активная позиция
`a` или исторический адрес без позиции), `[silent]`, а для погоды — `[upkeep]`.
Неизвестные/дублированные теги, аргументы после аннотаций, `[persistent]`, стороны
p3/p4 и позиции doubles отклоняются. Upkeep с none или новым источником отклоняется.
Некорректные новые события возвращают MalformedServerEvent без текста входа в
причине; reducer включает существующую sticky-блокировку без частичной мутации.

## Покрытие и ограничения

Поддержаны четыре погоды, четыре terrain, четыре общих поля, десять условий сторон,
два сообщения полевых активаций и одна узкая активация Court Change. Матрица
помечает weather/field/side-conditions как partial. Семейство effect-context также
partial из-за Court Change; остальные activate/block ещё относятся к PR 5.

Сохраняются блокировки Hail/primal weather, G-Max/pledge/legacy условий, Fairy Lock,
Ion Deluge, Delta Stream и неизвестных подтипов. Perish Song в целом не объявляется
поддержанным: perishN остаются вне реестра PR 3; Teatime требует будущей обработки
предметов. Погодные способности записываются только как источник сообщения,
не превращаются в полную модель раскрытой/подавленной способности.

Окружение пока не добавлено в интерфейс: визуализация и локализованный журнал
остаются PR 8. Новые события не подтверждают выбор, не меняют requestRevision и
не разрешают повторную отправку. Повторный request не снимает unsupported.

## Проверки

- 27 тестов модели/редуктора: все реестры, замена погоды и terrain, слои,
  Court Change, метаданные, снятие, ограниченность активаций, неизменяемость,
  сохранение при switch/drag/faint/request, изоляция комнаты/epoch/stale/terminal.
- Три теста декодера с таблицами валидных и ошибочных форм и проверкой маршрутизации.
- Шесть прежних guard-сценариев заменены промежуточными положительными проверками.
  Добавлены environment-lifecycle, environment-unknown, environment-layer-overflow;
  mechanics_scenarios теперь содержит 38 сценариев. Проверяется реальная отправка
  через существующий FakeSocket → session → controller, без второго reducer в тестах.
- Сценарии синтетические, формы сверены с закреплённым upstream. Публичные матчи
  и полная серверная приёмка в этом PR не запускались.

Результат: `dart format --output=none --set-exit-if-changed .` — **172 файла**,
без изменений; `flutter analyze --no-pub` — без замечаний;
`flutter test --no-pub` — **586 passed, 7 opt-in skipped**.
`git diff --check` пройден. Проверка upstream snapshot подтвердила 83
документированных типа, 77 литеральных типов и 509 записей наборов.
