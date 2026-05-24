# xStatsClass v1.1.7

**Author:** Andymon & .alur

## Description

Expression engine used by the x* modules (especially xLabel/xPopup) to resolve `[function(args)]` tokens and conditional blocks inside text. Provides system stats (CPU/mem/disk/network), media info (Winamp), date/time formatting, text helpers, and file utilities. Exported through the `processStatsRequest` API for other modules.

## Configuration

The module has no RC variables of its own. It is loaded to satisfy dependencies; functions are invoked from other modules via `[name(arg,...)]`.

## Supported Functions

All names are case-insensitive and can be nested. A `dynamic` result means the caller should poll/refresh periodically.

- **System / Hardware**: `cpu([core])`, `cpuspeed([core])`, `cpuinfo`, `memtotal`, `memavailable`, `meminuse`, `swapavailable`, `swapinuse`, `swaptotal`, `os`, `osex`, `battery`, `powersource`, `uptime`, `connected`, `computername`, `username`, `mousepos`, `kblayout`, `skblayout`, `keyboardstate(<caps|num|scroll lock>)`.
- **Disk / Files**: `diskavailable(<path>[,units])`, `diskinuse(<path>[,units])`, `disktotal(<path>[,units])`, `fileexists(<glob>)`, `firstline(<file>)`, `lastline(<file>)`, `line(<file>,n)`, `linecount(<file>)`, `matchline(<file>,text)`, `randomline(<file>)`, `datecreated(<file>[,format])`, `datelastmodified(<file>[,format])`, `size(<path>[,units])`.
- **Network**: `hostname`, `ip([n])`, `online(<host> <url>)`, `netadaptername([index])`, `netin/out/inout([adapter],[units])`, `nettotalin/out/inout([adapter],[units])`, `internettime`.
- **Date / Time**: `date([format[,locale]])`, `time([format[,locale]])`, `uptime`, `itime` (Swatch beats), `size`/`uptime` unit helpers `bytes|kb|mb|gb|%`.
- **Audio / Winamp**: `volume([mixer|winamp])`, `mute`, `winampsong`, `winampartist`, `winamptitle`, `winamptime`, `winampremaintime`, `winamptotaltime`, `winampstatus`, `winampbitrate`, `winampsamplerate`, `winampplaying`, `winamppaused`, `winampstopped`, `winamprepeat`, `winampshuffle`, `winamprating`, `winampalbum`, `winampgenre`, `winampalbumtrack`, `winampyear`, `winampcomment`.
- **Motherboard Monitor (MBM)**: `mbmtemperature(<index|name>)`, `mbmcpuusage(<index|name>)`, `mbmfanspeed(<index|name>)`, `mbmvoltage(<index|name>)`, `mbmloaded`.
- **Window / Clipboard**: `activetask([fallback])`, `tasks([delimiter])`, `windowtitle(<class|hwnd>)`, `clipboardtext`.
- **Text Utilities**: `capitalize`, `lowercase`, `uppercase`, `trim([chars])`, `remove(<text>,<target>)`, `replace(<text>,<search>[,<with>])`, `after/afterlast(<text>,<search>)`, `before/beforelast(<text>,<search>)`, `between(<text>,<start>,<end>[,default])`, `verticaldown/up`, `exportedevar(<name>)`, `hideifempty(<text>)`, `empty(<text>)`, `notempty(<text>)`, `semicolon`, `dollar`.
- **Conditionals**: `if(...)`, `elseif(...)`, `else`, `endif`, plus `ifeval`/`elseifeval` for comparisons. These control output masking while the expression is parsed.

All byte-size functions accept optional `units` (1=bytes,2=KB,3=MB,4=GB,5=%). Network adapters are zero-based indices; omit to use the first adapter.

## Bang Commands

None; all interaction happens via expressions.

## Notes

- Consumed by other modules (xLabel/xPopup/xTray/etc.); load it before modules that request stats.  
- Some functions spawn background samplers (CPU/net); they set outputs as dynamic so callers know to refresh.
