# Предметы, способности и источники эффектов: PR 5

Дата: **5 ноября 2026 года**. Задача [#59](https://github.com/SlowBroshka/pokemon_showdown_client/issues/59).
Основа: [контракт механик](battle-mechanics-contract.md), [публичные появления](battle-participants.md),
[эффекты покемонов](battle-effects.md) и [окружение боя](battle-environment.md).

## Подробный план, изложенный до реализации

1. Различать неизвестный, известный удерживаемый и отсутствующий предмет.
   Сохранять последнее исчезновение и его причину. Аннотация лечения не должна
   возвращать уже съеденную ягоду в состояние «держит предмет».
2. Обработать раскрытие, расходование, удаление, восстановление и проверенные
   передачи/обмены. Frisk только раскрывает предмет цели. Сообщение передачи
   проверяет обе стороны до изменения любой из них.
3. Хранить публично сообщённую способность, прежнюю при явной замене и независимую
   отметку подавления. Поддержать Intimidate boost и атомарный Skill Swap без
   вывода базовой способности из вида/приватной команды.
4. Сохранять структурированные источники событий здоровья, статусов, усилений
   и окружения с appearance ID при доказанной связи. Ограничить историю, не
   копировать raw-протокол или приватные запросы в публичную модель.
5. Реализовать проверенные activate/block: Substitute damage, Trick/Switcheroo,
   Skill Swap, Ability Shield, защитные способности и ограниченный набор простых
   уведомлений. Исправить Good as Gold на фактическую форму -immune [from].
6. Новое появление получает неизвестные предмет/способность; старое сохраняет
   снимок. As One, Neutralizing Gas и неоднозначный перенос подавления через
   Baton Pass остаются guarded; формы и Transform относятся к PR 6.
7. Перевести пять прежних guard-сценариев в положительные; добавить проверки
   расходования/восстановления, передач, источников, атомарности, истории,
   приватности и защиты выбора. Сохранить request-only авторизацию.
8. Обновить матрицу, документацию, выполнить format/analyze/full tests и
   опубликовать PR через SlowBroshkas-bot / Primary.

## Источники и уточнения

Закреплён Showdown
[`b354a81f11003a03f0dcd1dafd4edc641e6763bd`](https://github.com/smogon/pokemon-showdown/tree/b354a81f11003a03f0dcd1dafd4edc641e6763bd).
Прочитаны исходники этого checkout, снимок PR 1 не менялся.

- [pokemon.ts](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/sim/pokemon.ts#L1804):
  eatItem/useItem посылают enditem, а setAbility — новую и старую способность с
  источником. Mummy/Lingering Aroma используют другую форму activate и остаются
  вне текущего реестра.
- [battle.ts: Skill Swap](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/sim/battle.ts#L1325):
  в Gen9 singles activate содержит актёра, **новую способность актёра**, прежнюю
  способность актёра и [of] второго участника. Присваивания применяются атомарно.
- [moves.ts: Trick](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L19860):
  activate предшествует отдельным item/enditem. По одному activate предметы
  не меняются. Switcheroo имеет ту же схему.
- [Covet](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L3100)
  и [Magician](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/abilities.ts#L2475):
  одного item получателя достаточно для доказанного удаления предмета у [of]
  донора. Для Frisk [of] — владелец Frisk, передачи нет. Pickpocket/Thief дополнительно
  посылают enditem донора; повторное подтверждение отсутствия допустимо.
- [Gastro Acid](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/moves.ts#L6430):
  endability в целевом поколении содержит только адресата. Подавление не стирает
  последнее известное имя; новое ability само по себе не снимает Gastro Acid.
- [Good as Gold](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/abilities.ts#L1634):
  использует immune с [from] ability. Пример PR 1 с block и лишними аргументами
  был синтетическим и неточным; исправлен по эмиттеру, не объявлен поддержанной формой.
- [Cud Chew](https://github.com/smogon/pokemon-showdown/blob/b354a81f11003a03f0dcd1dafd4edc641e6763bd/data/abilities.ts#L742):
  повторяет enditem для запомненной ягоды, не снимая текущий предмет. Поэтому
  Cud Chew исключён из простых активаций: безопасная поддержка требует отдельного
  состояния. Это уточнение сделано при реализации, до публикации.

## Представление публичного знания

`ObservedPokemon.traits` — неизменяемый PokemonTraits. В новом появлении поля пусты.

| Поле | Смысл |
| --- | --- |
| itemKnowledge | unknown / held / absent |
| item | публично известный удерживаемый предмет; null при unknown/absent |
| lastEndedItem | последнее явно исчезнувшее название, историческая запись |
| itemEndReason | consumed / removed / transferred / ended |
| ability | последнее явно сообщённое текущее имя; не исходная способность вида |
| previousAbility | прежнее имя из сообщения явной замены, не догадка |
| suppressed | наблюдалось endability; это не вычисление глобального подавления |

`ended` используется, когда событие не уточняет причину (например, обычный enditem
Air Balloon). `[eat]`, `[weaken]`, gem и stealeat означают consumed. Bug Bite/Pluck
не присваивают съеденную ягоду удерживаемым предметом атакующего. Knock Off,
Corrosive Gas, Incinerate и Fling относятся к removed. Перенос/обмен — transferred.
После восстановления itemKnowledge снова held, lastEndedItem остаётся историей.

Передачи поддержаны для Covet, Thief, Bestow, Magician и Pickpocket. Если известный
предмет донора противоречит передаваемому или участник не найден, обе стороны
остаются неизменными и включается блокировка. Trick/Switcheroo применяют отдельные
серверные item/enditem по мере поступления; activate не угадывает итог обмена.
Восстановление поддержано для Harvest, Pickup, Recycle.

Изменения способности принимают источники Trace, Role Play, Entrainment, Worry Seed,
Simple Beam; третье поле без такого источника разрешено только как `boost` для
Intimidate. Skill Swap использует сообщённые имена, даже если способности ранее
не были раскрыты. Пустые скрытые имена из allied/doubles-формы отклоняются.

HP/status/Tera/faint сохраняют traits текущего появления. Switch/drag создают
новое неизвестное знание, даже если публичное имя совпало с прежним. Старое появление
сохраняет снимок; приватный request не дополняет публичные предметы/способности.
Baton Pass с наблюдённым подавлением блокируется: Gastro Acid копируется с
исключениями, и переносить bool на неизвестную новую способность было бы неверно.

## Контекст и источники

`BattleState.effectObservations` содержит последние 200 неизменяемых записей:
тип события, ход, PublicEffectSource(kind/name/ofIdent), адресат, его appearance ID
и sourceAppearanceId при доказанном владельце. Ссылки могут пережить вытеснение
старого появления из ограниченного реестра, как существующие ссылки журнала.

Прямые trait-события сохраняют контекст в BattleTraitEvent. Поддержанные события
здоровья, статусов, ступеней и окружения с [from] оборачиваются в
BattleAttributedEvent(inner, source); типизированная внутренняя полезная нагрузка
остаётся неизменной. Проверка контекста предшествует применению inner; невалидный
источник не оставляет частичного изменения HP/ступеней/окружения.

Семейства аннотаций: damage/heal/sethp, status/curestatus, boost/unboost/setboost,
clearboost/clearnegativeboost/clearpositiveboost, copyboost/swapboost/invertboost,
weather, fieldstart/end, sidestart/end. Immune с [from] разбирается отдельным
trait-событием. Это не универсальное принятие аннотаций всех типов протокола.

Правила атрибуции проверенных форм:

- У обычных item/ability-источников [of] указывает владельца; без [of] используется
  адресат. Для move без явного [of] владелец не угадывается; condition/recoil/drain
  сохраняются без назначения владельца.
- У item от Magician/Pickpocket актёр — владелец способности, [of] — донор предмета.
  У Frisk владелец способности — [of]. У Trace [of] — скопированный покемон,
  владелец Trace — актёр. У enditem с источником владелец консервативно не назначается.
- Публичная метка неактивного [of] в обёрнутом событии сохраняется без привязки
  к произвольному прошлому появлению. Неизвестный активный [of] блокируется.

**Наблюдение не является новым присваиванием текущего предмета/способности.**
Лечение после enditem Sitrus Berry не восстанавливает ягоду. Rocky Helmet/Good as
Gold/Ability Shield могут быть записаны как свидетельство, при этом traits остаются
unknown до явного item/ability. Это намеренное разделение истории источников и
утверждений о текущем состоянии, пригодное для будущего UI без ложных выводов.

Публичная модель не содержит rawLine, полного data или приватной команды. Имена
и формы проверяются декодером; причины ошибок не включают входные данные.
Никакие эти записи не подтверждают отправленный выбор и не меняют requestRevision.

## Реестр активаций и границы

Поддержаны Substitute `[damage]` (только при наблюдённом Substitute),
Trick/Switcheroo `[of]`, Skill Swap с двумя именами, Quick Claw, Ability Shield,
Aroma/Flower/Pastel/Sweet Veil, и простые формы `ability: NAME` для:

Emergency Exit, Guard Dog, Hadron Engine, Healer, Hydration, Immunity, Insomnia,
Lightning Rod, Limber, Magma Armor, Oblivious, Orichalcum Pulse, Own Tempo,
Pastel Veil, Quick Draw, Ripen, Screen Cleaner, Shed Skin, Sticky Hold, Storm Drain,
Suction Cups, Synchronize, Telepathy, Thermal Exchange, Toxic Debris, Vital Spirit,
Water Bubble, Water Veil, Wimp Out.

Это сообщения о срабатывании: изменения статусов, ступеней, поля и замены поступают
отдельными событиями. Court Change сохраняет обработчик PR 4. Неизвестные формы
activate/block по-прежнему блокируют управление.

Не поддержаны As One/Neutralizing Gas, Cud Chew, Mummy/Lingering Aroma, Symbiosis,
сложные формы Protosynthesis/Quark Drive, формы/Transform и глобальное вычисление
подавления. Альтернативный Orichalcum Pulse `[source]` также остаётся вне реестра.
Передача Sticky Barb без сообщения не реконструируется; предметы не объявляются
полной симуляцией инвентаря сервера. Покрытие items/abilities/effect-context остаётся
partial; оставшиеся случаи должны быть рассмотрены до общей приёмки PR 9.

UI и русский журнал остаются PR 8. Публичные матчи и повторная полная серверная
приёмка в этом PR не запускались; fixtures синтетические, сверены с pinned source.

## Проверки

- Тесты предметов и способностей: жизненный цикл, Frisk/передачи/обмены,
  Skill Swap/Trace, подавление, наблюдения источников, история, приватный request,
  атомарность ошибок, лимит и неизменяемость истории, изоляция комнаты/epoch/stale/terminal.
- Четыре проверки декодера с таблицами форм: прямые типы, обёрнутые источники,
  ошибочные поля/теги, область комнаты и сохранение владения Court Change.
- Пять прежних guard-сценариев заменены проверками промежуточного состояния.
  Добавлены traits-transfer, traits-unknown, traits-source-atomicity; mechanics
  corpus теперь содержит 41 сценарий. Проверяются реальные команды socket sink.

Итог: **619 passed, 7 opt-in skipped** (`flutter test --no-pub`), анализатор без
замечаний, форматирование **179 Dart-файлов** без изменений, `git diff --check`
пройден. Снимок upstream подтверждён: 83 документированных типа, 77 литеральных
типов, 509 записей наборов. После уточнения ссылки Good as Gold в матрице
исполняемый корпус дополнительно проверен отдельно.
