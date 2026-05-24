=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    AnyKey 1.0
    Copyright(c) Sergey Gagarin a.k.a. Seg@
    Kirov, Russia  2004
    Based on jKey module sources
    by Chris Rempel (jugg; jugg@dylern.com) and
    Eric Moore (hollow; hollow1@subdimension.com)

    README
=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

=-=-=-=-=-=-=-=-=-=-=-=-=
The Table of Content
=-=-=-=-=-=-=-=-=-=-=-=-=
  I. INTRODUCTION
 II. INSTALLATION
III. CONFIGURATION
 IV. LICENSE
  V. CONTACTS

=-=-=-=-=-=-=-=-=-=-=-=-=
I. INTRODUCTION
=-=-=-=-=-=-=-=-=-=-=-=-=

AnyKey.dll is alternative hotkey manager for LiteStep.
It is developed as the replacement for well-known jKey
hotkey manager, i.e. included 99% of it's features.
The reason why it was coded is that I have Genius BTC
keyboard and wanted to have got ALL things I can do
with it :)

So the features added:

*ScanKey <modifiers> <key> <command>
the same thing as *Hotkey, but it works with low-level
keyboard input, so extra multimedia keys that hasn't
been mapped to the system Virtual Keys table by
keyboard driver (jugg's ScanKey shows 0xFF) can be
used with it. To determine physical scancode of a key
use ScanKey2 tool. It can be found in the module
archive.
You may use this config line only with described keys,
i.e. if Virtual Key isn't 0xFF the *ScanKey shorcut
will not work. It is disabled because some of such
keys has the same scan code as 'regular' keys like 'o'
or '/'.
Also note that *ScanKey will work only in WinMe, Win2k
or higher and doesn't work on Win95/98/98SE and NT 4.0
due limitation of the implementating method.

*AppKey <modifiers> <key> <command>
Windows OS tries to map all extra multimedia keys to
the AppCommand table. It isn't only keys on your
keyboard, but on 'advanced' mice and some other
devices too.
The complete list of APPCOMMANDS is available in the
vk104.txt distributed with the module.
Use these IDs as the values for the <key> field.
*AppKey feature works only with Win2k and higher.

=-=-=-=-=-=-=-=-=-=-=-=-=
II. INSTALLATION
=-=-=-=-=-=-=-=-=-=-=-=-=

I hope you already have OTS2 distro.
Else you'll need to update your LiteStep or do
everything by hand (i.e. w/out my help :) )

So, InstallShield: ;)
1) Find your personal dir. Usually it is situated
   directly in the \LiteStep\ dir for single-user
   configuration or in the
   \LiteStep\profiles\<your login name>\
   or in the
   \Documents and Settings\<your login name>\Application
   Data\LiteStep\
   folder for multiple-user configuration
2) create \Personal\Anykey subfolder
3) copy \docs\vk104.txt from this archive to the created
   directory
4) open \Personal\personal.rc
5) find and replace the
   *NetLoadModule    jkey-xxx
   line with the following:
   *NetLoadModule    anykey-1.0
6) remove the
   jKeyUseHotkeyDef
   line
7) if you enabled jKeyLWinKey and jKeyRWinKey options,
   rename them to the AnyKeyLWinKey and AnyKeyRWinKey.
8) change
   jKeyVKTable         "$PersonalDir$jkey\vk104.txt"
   line to the
   AnyKeyVKTable         "$PersonalDir$anykey\vk104.txt"

That's all!


=-=-=-=-=-=-=-=-=-=-=-=-=
III. CONFIGURATION
=-=-=-=-=-=-=-=-=-=-=-=-=

If you're already know jKey module settings, it very
simple to migrate. Just replace jKey--- prefix to the
AnyKey--- and remove jKeyUseHotkeyDef definition
since it cannot be disabled.


AnyKeyVKTable "vk104.txt"
  - Sets the Virtual Key code lookup table text
    file that AnyKey will reference for special key
    specifiers.

  - Accepts any valid formatted test file that
    contains a Virtual Keycode lookup table.

    Text file format:
    - One entry per line in the following format.

      <keyname> , <hexvalue>

      The <keyname> is a string value representing
      the virtual key code (<hexvalue>). <keyname>
      is used in the *HotKey definition in place of
      <hotkey>.

      The <hexvalue> is the Virtual Key Code,
      represented in Hexidecimal format.

  - Defaults to: no default

AnyKeyLWinKey "!Popup"
  - Sets the command to be executed when the
    LEFT WinKey is pressed by itself.

    *Note: Command will be executed after the time
           specified by "AnyKeyLWinKeyTimeout"
           setting.

    *Note: "AnyKeyLWinKey" does not execute anything
           by default and so, must be set for it to
           execute anything.

  - Accepts any !Bang command or Executable.

  - Defaults to: no default


AnyKeyRWinKey "!Popup"
  - Sets the command to be executed when the
    RIGHT WinKey is pressed by itself.

    *Note: Command will be executed after the time
           specified by "AnyKeyRWinKeyTimeout"
           setting.

    *Note: "AnyKeyRWinKey" does not execute anything
           by default and so, must be set for it to
           execute anything.

  - Accepts any !Bang command or Executable.

  - Defaults to: no default


AnyKeyLWinKeyTimeout 750
  - Sets the delay from the time the LEFT WinKey is
    pressed to the time the command specified by
    "AnyKeyLWinKey" is executed.

  - Accepts any positive integer in milliseconds.

    *Note: Anything less the 400 will probably will
           cause things to behave erratically.

  - Defaults to: 750


AnyKeyRWinKeyTimeout 750
  - Sets the delay from the time the RIGHT WinKey
    is pressed to the time the command specified by
    "AnyKeyRWinKey" is executed.

  - Accepts any positive integer in milliseconds.

    *Note: Anything less the 400 will probably will
           cause things to behave erratically.

  - Defaults to: 750


AnyKeyNoWarn
  - If Set no warning will be issued when a hotkey
    fails to register correctly.

  - boolean value: true if set, otherwise false.


*Hotkey
*Scankey
*Appkey
  - parameters: <modkey> <hotkey> <command>

    <modkey> can be one or more of the following
             seperated by a plus (+) sign. Spaces
             are not allowed.

      CTRL, SHIFT, WIN, ALT

    <hotkey> can be any alpha numeric key or an
             identifier listed in the
             "AnyKeyVKTable" lookup file if one is
             being used.

    <command> can be any !Bang command or
              executable that is to be executed
              when the specified key combination
              is pressed.

  - Multiple settings of this command are
    allowed and the maximum number is limited by
    system memory.

  - It is used to define the Hotkeys and the
    commands to be executed when the hotkey
    sequence is pressed.


=-=-=-=-=-=-=-=-=-=
IV. LICENSE
=-=-=-=-=-=-=-=-=-=

1) This product distributed under GNU GPL license.
2) If this module erased all data from your hard disk,
   it isn't my module, it was coded by mr.X and
   published with my name :(

=-=-=-=-=-=-=-=-=-=
V. CONTACTS
=-=-=-=-=-=-=-=-=-=

If you have any suggestions or just want to beat my face,
it is possible to find me:
- at ICQ: 162261148
- at the Chuvi's website: http://www.litestep.bip.ru/
                          [only in Russian]
- or via mail: inform-sega@freemail.ru


Hmmm... did I miss something to say? No?
So wish you luck with a playing this toy.