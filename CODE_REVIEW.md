# zControls code review

Review of the units in `Source/`: bugs, memory leaks and performance.

- **Date:** 2026-11-13.
- **Method:** static reading of every unit. VCL and RTL behaviour that a finding relies on was checked against the Delphi 12 source: `TCustomListBox.SetSelected`, focus removal when a focused control is hidden, `TCustomForm.SetActiveControl` and `TComponent` free notification. Fixed items are covered by a test program (see Tests below). Open items come from reading the code unless noted.
- **Line numbers:** they refer to the working tree *after* batch 1. Links like `L1535` point into `Source/zObjInspector.pas` unless another file is named.

Most of the serious problems come from two design flaws, both now fixed:

- The inspector hands out raw `PPropItem` pointers into a list (`FItems`) that it frees and rebuilds wholesale (crash #2).
- It had no way to find out when the inspected object was freed (crash #1, fixed for `TComponent`).

## Status

| # | Finding | Status |
|---|---------|--------|
| 1 | Inspected object freed while inspected | **Fixed** in 60b4730 for `TComponent`. Plain `TObject` relies on the caller. |
| 2 | `PPropItem` pointers dangle after a rebuild | **Fixed** in 90c15b2. |
| 3 | `SetPropValue` with nothing selected | **Fixed** in a2f2928. |
| 8 | `UpdateEditControl` always calls `SetFocus` | **Fixed** in a2f2928. |
| 7 | Tab key taken from every application | **Fixed** in 4f05fd6. |
| 5 | `TStackEx<T>.Get` stack overflow | **Fixed** in c26d7c1. |
| 6 | Down arrow in an open dropdown raises `EListError` | **Fixed** in 105f4c7. |
| 10 | Destructor frees its lists before the editor goes | **Fixed** in fa57bc5. |
| 9 | Setting `Font` before `Parent` raises | **Fixed** in df704ee. |
| 4 | Popup list freed inside its own handler | **Corrected:** not reachable today; the real bug is that component-reference dropdowns don't work. |

With #9, every crash in the original list is fixed or corrected. The remaining sections (memory leaks, functional bugs, performance, minor) are open, except for the items marked FIXED in them.

| Functional bug or leak | Status |
|------------------------|--------|
| Invalid numbers silently became 0 | **Fixed** in 41dd078. |
| `TDateTime`, `TDate`, `TTime`, `Currency` and other float types became 0 | **Fixed** in 99eb2ca. |
| `TzObjectHost` leaked when the inspector was freed | **Fixed** in 0c5c3f8. |
| Batch 1: every remaining leak, 12 small functional bugs, 4 minor items | **Fixed** (uncommitted); marked "FIXED (batch 1)" below. |

**Still open after batch 1:**

- **Functional:**
  - component references can't be set (#4);
  - one raising getter breaks the whole paint;
  - some edits are lost (`FTxtChanged`);
  - non-visual components get blank events (`GetFormRoot`);
  - `ExpandAll` doesn't stick;
  - category registrations are wiped;
  - sets beyond element 31;
  - `MouseMove` overwrites `Hint`;
  - the "non-default" bold.
- **Design:** `FloatPreference` is shared by every inspector.
- **Minor:** `GetValue` over-reads; `IsCircularLink` visibility.
- **Performance:** all items.

## Tests

`InspectorTests.dpr` is a console program that drives a real form and inspector. It currently lives in the session scratchpad and should be moved into the repo.

- **Coverage:** 253 checks, passing on Win32 and Win64. The batch 1 tests were also run against the previous commit, and each one failed there apart from the single-monitor dropdown sanity check.
- **`PoisonMM.pas`:** a test-only memory manager that is the first unit in the program's `uses`.
  - It fills every freed block with `$80` and never reuses it, so any use-after-free becomes an access violation at `$80808080`.
  - Without it, FastMM hands a freed `TPropItem` straight back for the next record of the same size, so a dangling pointer usually reads a valid (wrong) record and nothing crashes.
- **Exceptions:** exceptions raised inside message handlers go to an `Application.OnException` sink and count as failures (unless a test declares it expects one), so a run never blocks on a dialog.

## Crashes and memory safety

### 1. No free notification on the inspected object - FIXED in 60b4730 (TComponent only)

**Was:**

- `SetComponent` stored a raw `TObject`, and nothing used `FreeNotification` or overrode `Notification`. When the inspected component was freed, or a component that an expanded row points to through `TPropItem.Instance`, the next paint called `Prop.GetValue` on freed memory ([L1259](Source/zObjInspector.pas#L1259)).
- Freed addresses also get reused: setting `Component` to a new object at the address of the freed one was ignored by `SetComponent`'s `Value <> FComponent` test.

**Fix** ([L1833](Source/zObjInspector.pas#L1833) to `ZCMRebuildItems` at [L1930](Source/zObjInspector.pas#L1930)):

- **Watching:** the inspector calls `FreeNotification` on the root component, each `TzObjectHost` member and every component reached through a property (`PopupMenu`, `Images`, `Action`...). This list is rebuilt by every `UpdateItems`.
- **Root freed:** `Component` becomes nil and the list is cleared immediately ([L1869](Source/zObjInspector.pas#L1869)).
- **Nested or hosted component freed:** the items are cleared immediately and rebuilt from a posted `ZCM_REBUILDITEMS` message.
  - It can't rebuild immediately: `Notification` runs inside the dying component's destructor, after its descendant destructors have run.
  - Components that reference it may not have been notified yet, so `Button.PopupMenu` can still return the dying menu.
  - A hosted object that is freed is also removed from the host with the new `TzObjectHost.RemoveObject`.
- **Editor:** before the items are dropped, the editor discards uncommitted text and its item pointer (`DetachEditor`, `TzPropInspEdit.Detach`). Committing is not safe here, because the target may be part-way through its destructor.
- **Not undone:** `RemoveFreeNotification` is deliberately never called. It removes the whole link between the two components, so it would also cut a link the VCL set up for itself (for example `Inspector.PopupMenu := X`). Old links clean themselves up when either side is freed, and `Notification` ignores components that are no longer watched.
- **Removed vs freed:** a component that's only removed from its owner, not freed, is left alone (the handler checks `csDestroying`).

**Still open:**

- **Plain `TObject` relies on the caller.** On Win32/Win64 there's no destruction callback, and `[weak]` only works for interface references. Detecting it would mean patching the class's VMT, which affects the whole process and was rejected. Whoever frees a plain object must first set `Component := nil`, or call `RemoveObject` on the host.
- **A nested plain object replaced by a setter is still a use-after-free.** `TPicture.SetGraphic` and `TPicture.LoadFromFile` free the old graphic, but the rows under an expanded `Picture.Graphic` still point at it. Either read `Instance` from the parent item each time it's needed (checking the class matches `Prop.Parent`), or run the `ItemNeedUpdate` check before painting.

### 2. `PPropItem` pointers dangle after every rebuild - FIXED in 90c15b2

**Was:**

- `UpdateItems` and `ComponentChanged` freed every record with `FItems.Clear`, while the editor's `FPropItem`, the popup list's `FPropItem`, an open dialog's `PropItem` and `FVisibleItems` still pointed at them.
- `UpdateEditControl` then hid the editor, and the VCL moves focus away from a hidden control immediately (`CMVisibleChanged` -> `RemoveFocus` -> `SetActiveControl(nil)`). That ran `WMKILLFOCUS` -> `DoSetValueFromEdit` on the freed record whenever the editor held uncommitted text.
- It was reachable through `UpdateProperties`, `CollapseAll`, `ExpandAll`, `ExpandItem` or a `Component` change when called from a popup menu, a shortcut or a timer, because none of those take focus.
- The +/- click that rebuilds in `MouseDown` left the editor attached to a freed record.

**Fix:**

- **`UpdateItems`** ([L1788](Source/zObjInspector.pas#L1788)) now commits the editor's pending text while the items are still valid (`CommitEditor`, [L3837](Source/zObjInspector.pas#L3837)), then detaches the editor and clears `FVisibleItems` before freeing the items. Callers re-attach the editor through `UpdateEditControl`.
  - If the commit itself rebuilds the items (a class property value), that inner rebuild finishes before the outer one starts.
  - Text that's rejected (an invalid value, or the setter raises) is reported with `Application.HandleException`. The text is then dropped and the rebuild the caller asked for still happens.
- **`SetComponent`** ([L1544](Source/zObjInspector.pas#L1544)) commits pending text to the *previous* component before switching. **`ComponentChanged`** ([L1517](Source/zObjInspector.pas#L1517)) detaches the editor before clearing the items.
- **`MouseDown`'s +/- rebuild** calls `UpdateProperties`, so the editor is re-attached ([L3161](Source/zObjInspector.pas#L3161)).
- **`ShowModalDialog`** ([L4207](Source/zObjInspector.pas#L4207)) tracks the open dialog, so a rebuild nils a `TzInspDialog`'s `PropItem`. After the dialog closes it continues with the re-attached item, or skips setting the value if the item no longer exists. It now uses try/finally.
- **Docs:** `Items` and `VisibleItems` are documented as freed by every rebuild: keep the `QualifiedName`, not the pointer.

**Behaviour to be aware of:** pending text is *committed* before a rebuild, as the old code intended through `WM_KILLFOCUS`. So a timer that calls `UpdateProperties` while the user is typing applies the half-typed text and resets the editor.

**Still open:** an event handler that rebuilds the items while the inspector is inside one of its own loops is not protected. For example:

- `KeyDown`'s search loop holds `LSelectedItem` across `DoSelectCaret` -> `SelectItem` -> `OnSelectItem` ([L3087](Source/zObjInspector.pas#L3087)).
- `SelectItem` reads `FVisibleItems[Index]` again after calling `OnSelectItem` ([L3576](Source/zObjInspector.pas#L3576)).

### 3. `SetPropValue` with nothing selected always crashed - FIXED in a2f2928

**Was:** `DoSetValue` always calls `FPropInspEdit.UpdateEditText` ([L2915](Source/zObjInspector.pas#L2915)), which dereferenced `FPropItem` without checking it. `FPropItem` is nil until a value row is selected, and it is also nil while a category row is selected. It was an access violation reading address `$24` (the offset of `FQName`).

**Fix:** `UpdateEditText` returns when there's no item ([L4264](Source/zObjInspector.pas#L4264)).

### 4. Component-reference dropdowns don't work (CORRECTED)

**Correction:** the original review said the popup list is freed inside its own `OnMouseDown` when a component reference is picked from it. A test probe showed that path isn't reachable today.

- `PropInfoChanged` makes the editor read-only for every class property ([L4136](Source/zObjInspector.pas#L4136)).
- `DoSetValueFromList` returns early when `ReadOnly` is set ([L4005](Source/zObjInspector.pas#L4005)).

**The real bug:**

- The dropdown for `PopupMenu`, `Images`, `Action` and similar properties lists the form's components, but clicking one does nothing. Verified: clicking `ProbeMenu2` left `Button.PopupMenu` nil.
- Typing a name does nothing either, and neither does deleting the text: the editor is read-only, so a reference can't be changed or cleared at all. (An earlier version of this review said deleting the text cleared it; it doesn't.)

**Fixing it makes the original crash reachable,** so the two have to be fixed together:

- The chain is `ListBoxMouseDown` ([L4316](Source/zObjInspector.pas#L4316)) -> `DoSetValueFromList` -> `DoSetValue` -> `UpdateProperties` (class property) -> `UpdateEditControl` -> `PropInfoChanged` -> `InitList` -> `FreeAndNil(FList)` ([L4288-4289](Source/zObjInspector.pas#L4288-L4289)). That frees the list while its `WMLButtonDown` is still running.
- Defer the list re-creation, or don't recreate the list when re-attaching to the same `QualifiedName`.
- `DoSetValue` must also clear the editor's pending-text flag (`FTxtChanged`) for the item being set. Otherwise the `CommitEditor` call in the rebuild that follows would overwrite the list choice with whatever had been typed.

### 5. `TStackEx<T>.Get` always recursed until the stack overflowed - FIXED in c26d7c1

**Was:**

- `TStackEx<T>.Get` read `Items[Index]`, and `Items` is `TStackEx`'s own property, backed by `Get`.
- `TzCanvasStack.Clear` calls it whenever the stack isn't empty ([zCanvasStack.pas:90-95](Source/zCanvasStack.pas#L90-L95)). `Clear` is called from `Invalidate` ([L1430](Source/zObjInspector.pas#L1430)).
- The stack was left non-empty by any exception during paint, because Push/Pop had no try/finally. So a property getter that raised was followed by a stack overflow on the next `Invalidate`.
- In the tests, the old `Peek(0)` killed the process outright; the overflow could not be caught.

**Fix:**

- `Get` reads `List[Index]` ([zCanvasStack.pas:225-228](Source/zCanvasStack.pas#L225-L228)).
- All five Push/Pop pairs are in try/finally: `PaintHeader` ([L2217](Source/zObjInspector.pas#L2217)), the `Paint` row loop ([L2465-2469](Source/zObjInspector.pas#L2465-L2469)), `PaintCategory` ([L3308](Source/zObjInspector.pas#L3308)), `PaintItemValue` ([L3540](Source/zObjInspector.pas#L3540)) and `PaintValue` ([L5055-5081](Source/zObjInspector.pas#L5055-L5081)).

**Still open:**

- A property getter that raises still makes the *whole* paint fail. It does so every time the inspector paints, which shows an error dialog for each `WM_PAINT`; see Functional bugs.
- `TzCanvasStack.Destroy` doesn't free leftover objects; see Memory leaks.
- Replacing the canvas stack altogether is still worthwhile for performance; see the performance section.

### 6. The Down arrow in an open dropdown raised `EListError` - FIXED in 105f4c7

**Was:** `TzPropInspEdit.WMKEYDOWN` limited the list index by the inspector's `VisiblePropCount` instead of `FList.Items.Count`.

- Open a Boolean dropdown, select True, press Down: `FList.Selected[2]` raised `EListError` ("List index out of bounds (2). TzPopupListBox range is 0..1").
- In long lists, such as colours, you couldn't arrow past row `VisiblePropCount - 1`.

**Fix:** Down is clamped to the dropdown's item count while the dropdown is open, and to the inspector's rows otherwise ([L4437-4441](Source/zObjInspector.pas#L4437-L4441), in `WMKEYDOWN` at [L4393](Source/zObjInspector.pas#L4393)).

### 7. The Tab key could be broken in every application - FIXED in 4f05fd6

**Was:**

- To make Tab start the type-to-search mode, the editor registered a system-wide `RegisterHotKey(Handle, 0, 0, VK_TAB)` whenever it got focus, and unregistered it on the last line of its `WMKILLFOCUS`.
- `DoSetValueFromEdit` runs earlier in that handler and can raise, for example on non-matching enum text ([L4081](Source/zObjInspector.pas#L4081)) or when the setter throws.
- So typing "xyz" into an enum and pressing Alt+Tab left Tab swallowed in every application.
- The next `RegisterHotKey` for the same keystroke then failed and set `FUnRegisterKeys := False`, so the hotkey was never released until the window was destroyed.
- Even when nothing went wrong, plain Tab was registered system-wide for as long as the editor had focus.

**Fix:**

- **No global hotkey:** `RegisterKeys`, `UnRegisterKeys`, `WMHotKey` and the `UnregisterHotKey` in `WM_DESTROY` are removed (they were `protected`; nothing outside the unit should have called them).
- **Tab claimed locally:** the editor answers `CM_WANTSPECIALKEY` for plain Tab ([L4503](Source/zObjInspector.pas#L4503)). That is how a VCL control keeps a key out of the form's dialog navigation.
- **Search started from the editor:** `WMKEYDOWN` handles `VK_TAB` by starting the search, exactly as `WMHotKey` did ([L4410](Source/zObjInspector.pas#L4410)). `WMCHAR` swallows the tab character that follows ([L4346](Source/zObjInspector.pas#L4346)).

**Behaviour kept:**

- Shift+Tab and Ctrl+Tab still move between controls.
- With `AllowSearch` off, Tab moves between controls.
- In search mode Tab moves to the next control, which is also what the old code actually did. Its "back to the editor" branch only ran when the hotkey had got stuck.

**Still open:** `WMKILLFOCUS` still lets the `DoSetValueFromEdit` exception escape, so rejected text shows an error dialog while focus is moving to another control or application. It no longer has any effect outside the application.

### 8. `UpdateEditControl` always called `SetFocus` - FIXED in a2f2928

**Was:** whenever a row was selected, every `UpdateEditControl` called `FPropInspEdit.SetFocus`, so `Component :=`, `UpdateProperties`, `ExpandAll` and the deferred rebuild from #1 all behaved badly:

- They raised `EInvalidOperation` ("Cannot focus a disabled or invisible window") when the inspector couldn't take focus, for example on a hidden tab.
- Otherwise they stole focus from whatever control had it.

**Fix** (`UpdateEditControl`, [L3760](Source/zObjInspector.pas#L3760)):

- **When focus moves:** the editor takes focus only when focus is already inside the inspector (`FocusIsInside`, [L3854](Source/zObjInspector.pas#L3854)). That means the inspector, its editor or its dropdown list. Clicks (`MouseDown` focuses the inspector first) and keyboard navigation in the editor keep working as before.
- **Restoring focus after a rebuild:** a rebuild hides a focused editor before `UpdateEditControl` runs, which moves focus to the form. `DetachEditor` ([L3871](Source/zObjInspector.pas#L3871)) records that the editor had focus, and `UpdateEditControl` restores it, but only if focus is still on the form and no other control has taken it since.
- **`CanFocus` guard:** `SetFocus` is also guarded by `CanFocus` ([L3820-3821](Source/zObjInspector.pas#L3820-L3821)).

**Behaviour change:** calling `SelectItem` from code no longer moves focus into the inspector. Call `Inspector.SetFocus` first if that is wanted.

### 9. Setting `Font` before `Parent` raised - FIXED in df704ee

**Was:** `CMFONTCHANGED` and `CMParentFontChanged` measured the row height with `Canvas.TextHeight`, which forces the control's window handle.

- Creating that handle needs a parent window, so both of these raised `EInvalidOperation` ("Control ... has no parent window"):
  - setting `Font` before `Parent`;
  - building a UI bottom-up, because `InsertControl` sends `CM_PARENTFONTCHANGED`. For example, parenting the inspector to a panel that wasn't parented yet.
- The row height also kept its old value, because the exception stopped `FItemHeight` being set.

**Fix:** the row height is measured with a screen DC and the inspector's font (`MeasureItemHeight`, [L2345](Source/zObjInspector.pas#L2345)). That needs no window handle and gives the same result as `Canvas.TextHeight`.

### 10. Wrong destructor order - FIXED in fa57bc5

**Was:** `TzObjInspectorBase.Destroy` freed all its lists before calling `inherited`.

- `TWinControl.Destroy` then calls `RemoveFocus`, which sent `WM_KILLFOCUS` to a focused editor. The editor then read the freed `FItems`/`FDefPropValue` while committing its pending text.
- Freeing the inspector while editing (for example from a keyboard shortcut or a toolbar button, neither of which takes focus) raised an access violation; in the tests it read `$80808080`.

**Fix** ([L1356](Source/zObjInspector.pas#L1356)):

- **Editor first:** the destructor calls `DetachEditor`, which drops the editor's pointers and moves focus out of it while everything is still valid.
- **Lists last:** they are freed *after* `inherited`, so the focus removal, window destruction and child-control destruction in `TWinControl.Destroy` can't reach freed state.

**Behaviour to be aware of:** text typed into the editor and not yet committed is discarded when the inspector is freed, because the inspected component may be part of the same teardown. A normal form close still commits it, because the form deactivates (and the editor loses focus) before anything is destroyed.

## Memory leaks

All memory leaks are fixed.

- **`TzObjectHost` - FIXED in 0c5c3f8.**
  - **Was:** the inspector freed a host when it was replaced ([L1547](Source/zObjInspector.pas#L1547)) or set to nil, but not in its destructor. Using the demo's "Multi components" button and then closing the app leaked it.
  - **Fix:** the destructor frees a host still assigned to `Component` ([L1391](Source/zObjInspector.pas#L1391)), after `inherited` like the other owned objects. The ownership rule (a `TzObjectHost` is owned, anything else is not) is documented on the `Component` property.
- **`SetFloatPreference` - FIXED (batch 1).**
  - **Was:** it stored the caller's object in the class var ([L187](Source/zObjInspector.pas#L187)) instead of copying it. The original object leaked, and the class destructor ([L4534](Source/zObjInspector.pas#L4534)) freed the caller's object; against the old code the tests end in runtime error 216 at shutdown.
  - **Fix:** it copies the settings with `Assign` ([L2004](Source/zObjInspector.pas#L2004)).
  - **Still open:** `FloatPreference` is a class var, so every inspector in the process shares it.
- **`UpdateItems` - FIXED (batch 1):** `LCategory` is now freed in a try/finally ([L1801](Source/zObjInspector.pas#L1801)), so a getter that raises no longer leaks it. `FItems` is still left half built in that case.
- **`ShowModalDialog` - FIXED in 90c15b2** (it now uses try/finally).
- **`TzCanvasStack.Destroy` - FIXED (batch 1):** it calls `Clear` first, which frees any brush, font and pen still saved ([zCanvasStack.pas:84](Source/zCanvasStack.pas#L84)).
- **Dialogs - FIXED (batch 1):** `TStringsDialog.InitDialog` ([zStringsDialog.pas:82](Source/zStringsDialog.pas#L82)) and `TGraphicDialog.InitDialog` ([zGraphicDialog.pas:103](Source/zGraphicDialog.pas#L103)) no longer leak when `PropItem` is set twice.

## Functional bugs

- **Component references can't be set from the dropdown or by typing a name.** See #4.
- **One raising getter breaks the whole paint.** `PaintValue` and `PaintItem` read property values directly, so an exception from any getter escapes `Paint`. In a real `WM_PAINT` that is an error dialog, then a repaint, then the same error, and none of the other rows are drawn. Getters that raise are common with `ObjectVisibility = mvPublic` (plain objects), and for some VCL properties in some states. The Delphi IDE instead shows the exception message as that row's value.
- **Invalid numbers silently became 0 - FIXED in 41dd078.**
  - **Was:**
    - `StrToValue` ignored the results of `TryStrToFloat`/`TryStrToInt64`, so `abc` set a number to 0.
    - Values outside the type's range reached the setter, which truncated them: 300 into a Byte stored 44.
    - `Int64` and `UInt64` properties were never parsed at all, because `TRttiInt64Type` is not `IsOrdinal`. Any text typed into them set them to 0. This wasn't in the original review; the tests found it.
  - **Fix** (`StrToValue`, [L5110](Source/zObjInspector.pas#L5110)):
    - Text that isn't a number, or is outside the property type's range, raises `InvalidPropValueError`, the same as non-matching enum text already did.
    - The new `TryParseOrdinal` ([L5202](Source/zObjInspector.pas#L5202)) works out each type's real range, Cardinal and UInt64 included. It accepts hex as a bit pattern for signed types, so `$FF00000F` typed into a `TColor` is still clBtnFace; that's also how `ColorToString` shows a system colour that has no name.
    - The raise lives in `RaiseInvalidValue` ([L5261](Source/zObjInspector.pas#L5261)), because a generic method declared in the interface can't use the implementation's exception class.
  - **Unchanged:**
    - Empty text still sets a number to 0 (an explicit branch in `DoSetValueFromEdit`, [L4041](Source/zObjInspector.pas#L4041)).
    - Values are rejected with an error rather than corrected.
- **`TDateTime`, `TDate`, `TTime`, `Currency` and other float types were set to 0 by any text - FIXED in 99eb2ca.** Found while testing the invalid-numbers fix.
  - **Was:**
    - These types displayed correctly, but `GetValueType` only recognises the exact `Single`/`Double`/`Extended` type infos ([L4929](Source/zObjInspector.pas#L4929)).
    - Every other float type, including distinct types such as `TMeasure = type Double`, fell through to the ordinal path. There `StrToValue` returned 0, and `GetValue` wrote it through the shared `TValue` storage.
    - Typing `4/03/2021` into a `TDateTime` stored 30/12/1899, `99` into a `Currency` stored 0, and invalid text was written as 0 too.
  - **Fix:**
    - `DoSetValueFromEdit` sends any other `tkFloat` property to the new `StrToFloatValue` ([L4103](Source/zObjInspector.pas#L4103), [L5266](Source/zObjInspector.pas#L5266)).
    - `StrToFloatValue` parses with the function that matches how `TValue.ToString` displays the type: `TryStrToDate`, `TryStrToTime` or `TryStrToDateTime` for the date types; `TryStrToCurr` for `Currency`; `TryStrToInt64` for `Comp`; `TryStrToFloat` otherwise.
    - It builds the value with the property's own type info, and rejects text it can't parse with `InvalidPropValueError`.
    - `Single`, `Double` and `Extended` keep their existing path.
- **Some edits are lost.** Edits made with Backspace, Delete or context-menu paste never set `FTxtChanged`: it is only set in `WMCHAR`, and the `vkBack` branch exits before setting it ([L4365-4369](Source/zObjInspector.pas#L4365-L4369)). Use `Change`/`EN_CHANGE` instead. This also affects the commit-before-rebuild from #2.
- **Text was always black - FIXED (batch 1).** `Font.Color := GetSysColor(clWindowText)` passed a `TColor` ($FF000008) as a system colour index, so `GetSysColor` returned 0, which was unreadable on dark or high-contrast themes. It's now `clWindowText` ([L4146](Source/zObjInspector.pas#L4146)).
- **Function-type events never listed handlers - FIXED (batch 1).** `PropSameMethodType` compared `LPType.ReturnType.Handle` with `AMethod.Handle` instead of `AMethod.ReturnType.Handle` ([L901](Source/zObjInspector.pas#L901)), so events such as `OnHelp` got no handlers.
- **Non-visual components get blank events and empty dropdowns.** `GetFormRoot` ([L1035](Source/zObjInspector.pas#L1035)) only resolves `TControl`, so `TMenuItem`, `TTimer` and `TDataSet` show blank event names and empty method/component dropdowns. The demo shows it with `PopupItemTest1` when events are enabled. Walk `TComponent.Owner` instead.
- **`ExpandAll` doesn't stick.** It ([L2919](Source/zObjInspector.pas#L2919)) records nothing in `FExpandedList`/`FSaveVisibleItems`, so the tree collapses on the next refresh.
- **A host forced category sorting - FIXED (batch 1).** Assigning a `TzObjectHost` set `FSortByCategory := True` permanently, so the next normal component was grouped too. `UpdateItems` now uses a local flag ([L1799](Source/zObjInspector.pas#L1799)), and `SortByCategory` is left alone.
- **Category registrations are wiped.** `ComponentChanged` ([L1517](Source/zObjInspector.pas#L1517)) clears every `RegisterPropertyInCategory` registration on each component change.
- **Search couldn't reach the last row - FIXED (batch 1):** `Index < FVisibleItems.Count - 1` is now `< FVisibleItems.Count` ([L2878](Source/zObjInspector.pas#L2878)), so Tab on the last row starts searching.
- **Sets:**
  - `TIntegerSet` limits sets to elements 0..31 ([L1023](Source/zObjInspector.pas#L1023), [L4612](Source/zObjInspector.pas#L4612), [L4778](Source/zObjInspector.pas#L4778)). Still open.
  - Set elements were ordered as strings ("10" before "2"), because their names used `IntToStr` and the list is sorted by name. FIXED (batch 1): the element number in the name is zero-padded ([L1687](Source/zObjInspector.pas#L1687)).
- **WideChar values above #255 were mangled - FIXED (batch 1).** `vtChar` wrote only `FAsUByte`, so a `PasswordChar` of '●' (U+25CF) became 'Ï' (U+00CF). It now writes `FAsUWord` for WideChar ([L4753](Source/zObjInspector.pas#L4753)).
- **Dropdown height was wrong on multiple monitors - FIXED (batch 1).**
  - **Was:** `ShowList` sized against `Screen.Height`, and the height went negative on a monitor below the primary.
  - **Fix:** it now fits the work area of the monitor the list opens on ([L4182](Source/zObjInspector.pas#L4182)).
  - **Test coverage:** the test only checks that the list fits on a single monitor; a multi-monitor setup couldn't be tested here.
- **`SetSplitterPos` didn't repaint or move the editor - FIXED (batch 1).** Setting it from code (not while loading) now calls a new virtual `SplitterMoved` ([L2134](Source/zObjInspector.pas#L2134)). The inspector overrides it to repaint and reposition the editor ([L3754](Source/zObjInspector.pas#L3754)).
- **`MouseMove` overwrites the control's own `Hint`/`ShowHint`** ([L3256-3279](Source/zObjInspector.pas#L3256-L3279)).
- **Wrong indentation for some objects - FIXED (batch 1).**
  - **Was:** `GetItemOrder` counted the dots in the item's qualified name. That name embeds `Object.ToString` and category names, so a `ToString` or category name containing '.' shifted the whole tree.
  - **Fix:** it now uses the item's depth below its top-level item, plus one inside a category ([L1404](Source/zObjInspector.pas#L1404)).
  - **Still open:** qualified names themselves still contain `ToString` and category names.
- **`TzInspDialog` was declared twice - FIXED (batch 1).** Dialogs derived from the `zObjInspDialogs` copy failed the `InheritsFrom` check and raised `DialogDerivedError`. `zObjInspDialogs.TzInspDialog` is now an alias of the real class ([zObjInspDialogs.pas:35](Source/zObjInspDialogs.pas#L35)), so existing code still compiles.
- **`VKeyToStr` mangled non-Latin-1 input - FIXED (batch 1).** It used `ToAscii` into a WideChar buffer. It now uses `ToUnicode`, with the flag that leaves dead-key state alone on Windows 10 1607 and later ([zUtils.pas:57](Source/zUtils.pas#L57)). Not covered by a test.
- **`MouseDown` could index with -1 - FIXED (batch 1):** it now exits when the rebuilt item is no longer visible ([L3145](Source/zObjInspector.pas#L3145)). Not covered by a test.
- **"Non-default" bold is misleading.** It means "changed since this row was first selected" ([L4277](Source/zObjInspector.pas#L4277)), not the RTTI `default` value.

## Performance (worst first)

1. **Every refresh rebuilds the whole object graph eagerly.** `UpdateItems` ([L1569](Source/zObjInspector.pas#L1569)) enumerates every nested class property, including component references (`PopupMenu`, `ActiveControl`, `Images`...), and calls every getter. It runs on every `UpdateProperties`: each class-property edit, `CollapseAll`, `ExpandItem`, `FloatPreference` changes. Enumerate children only when a node is expanded.
2. **Tree navigation is O(n).**
   - `TPropItem.Count` and `Items[]` ([L1098-1244](Source/zObjInspector.pas#L1098-L1244)) each do `FItems.IndexOf(@Self)` plus a scan, and `Items[]` allocates a `TList` on every call.
   - `UpdateVisibleItems` evaluates `PItem.Count > 0` for every item before the cheap `FIsSettingComponent` test ([L1985](Source/zObjInspector.pas#L1985)), so every refresh is O(n²).
   - Expand/collapse is O(k·n).
   - Store parent/child indices (or a child list) while building.
3. **Linear string lookups inside those loops.** `TList<string>.Contains` is used on `FExpandedList`, `FSaveVisibleItems` and `FCircularLinkProps`. Use `TDictionary<string, Boolean>`.
4. **Paint does RTTI work for every row.**
   - `GetValueType`, which calls the property getter, runs about 5 times per row via `ExtraRect`/`ValueTextRect`/`HasButton`.
   - `HasChild` ([L1142](Source/zObjInspector.pas#L1142)) creates a `TRttiContext` and runs `GetUsedProperties` for every class-typed row on every paint ([L974-990](Source/zObjInspector.pas#L974-L990)).
   - `ValueName` is computed 2-3 times per row.
   - `GetFirstItemIndex` ([L2387](Source/zObjInspector.pas#L2387)) makes a `GetScrollInfo` call for every rect.
   - Compute the value, type and name once per row per paint.
5. **`GetUsedProperties` is O(p²)** ([L5432-5462](Source/zObjInspector.pas#L5432-L5462)) and grows its array one element at a time with `SetLength`.
6. **`TzCanvasStack` creates and frees a TBrush, TFont and TPen per push**, about 3 pushes per row per paint, plus `Canvas.Refresh`. `SaveDC`/`RestoreDC`, or saving just the 4 properties that are actually changed, is cheaper and removes crash #5.
7. **`InitList` recreates the popup listbox whenever the editor is attached to an item** ([L4282](Source/zObjInspector.pas#L4282)). It forces window creation and repopulation (about 250 items for ShortCut) even if the list is never dropped down. Since the #2 fix this also happens after every rebuild, because the editor is always detached first. Create it lazily in `ShowList`.
8. **Smaller:**
   - `DrawHorzDotLine` ([zUtils.pas:74-84](Source/zUtils.pas#L74-L84)) does one MoveTo/LineTo per 2 pixels. Use a `PS_ALTERNATE` pen.
   - `GetSelectedItem` does a linear `SameText` scan ([L3019](Source/zObjInspector.pas#L3019)).
   - `Invalidate` invalidates twice ([L1429](Source/zObjInspector.pas#L1429), [L1432](Source/zObjInspector.pas#L1432)).

## Minor and latent

- **`TPropItem.Empty` - FIXED (batch 1):** it used `ZeroMemory` on a record that contains a string, and now uses `Default(TPropItem)` ([L1082](Source/zObjInspector.pas#L1082)).
- **`GetValue(const Value)` over-reads.** It reads 8 bytes through the untyped parameter regardless of the caller's variable size (Boolean, TColor, TObject on Win32) ([L4787-4790](Source/zObjInspector.pas#L4787-L4790)). It only works because `AsOrdinal` later reads the low bytes.
- **`IsCircularLink`** checks visibility against `LComponent` instead of the object being inspected ([L1627](Source/zObjInspector.pas#L1627)).
- **`UpdateButton` - FIXED (batch 1):** it tested `> VisiblePropCount` where it should test `>=` ([L4250](Source/zObjInspector.pas#L4250)).
- **`TzCanvasStack.Create(Collection)` - FIXED (batch 1):** it left the two internal stacks unbalanced, so `Peek` raised "Unbalanced stack". It now pushes each canvas ([zCanvasStack.pas:72](Source/zCanvasStack.pas#L72)).
- **`FloatConv_impl.inc` - FIXED (batch 1):** it indexed `Str[1]` without checking for an empty string, so whitespace-only input raised an access violation. It now checks first ([L46](Source/FloatConv/FloatConv_impl.inc#L46), [L90](Source/FloatConv/FloatConv_impl.inc#L90)). It is dormant anyway, because `CUSTOMFLOATCONV` isn't defined in the packages. When it is defined, `MyFormatFloat` also compiles a `TRegEx` on every call (still open).
- **Unused code:** `zBase.TzToolWindow`/`TzPopupWindow` aren't used by the library, and `zObjInspDialogs` is now only an alias kept for compatibility.
