# osu-thumbnails-cache-maker

## 한국어

### 소개

`cache.ps1`은 **osu!stable**의 `Data\bt` 폴더에서 사용하는 Beatmap thumbnail cache를 대량으로 생성하기 위한 PowerShell 스크립트입니다.

`Songs` 폴더에 보유하고 있는 beatmap을 검사하고, 각 mapset의 `.osu` 파일에서 배경 이미지를 찾아 osu!stable thumbnail 형식으로 변환합니다.

생성되는 파일:

```text
osu!\Data\bt\
├── 123456.jpg
└── 123456l.jpg
```

- `123456.jpg` → 80 × 60
- `123456l.jpg` → 160 × 120

### 주요 기능

- `Songs` 폴더의 mapset을 자동으로 검색
- 같은 mapset 폴더의 **모든 `.osu` 난이도 검사**
- `BeatmapSetID:-1`인 난이도가 있어도 다른 난이도에서 정상 SetID 검색
- 여러 난이도에서 얻은 SetID를 비교하여 mapset ID 결정
- `.osu`의 `[Events]` 섹션에서 background 파일 탐색
- JPG / JPEG / PNG / BMP / GIF / TIFF 이미지 처리
- 배경 이미지를 4:3 비율로 중앙 crop
- 80×60 및 160×120 JPEG thumbnail 생성
- 기존 thumbnail을 검사하여 불필요한 재생성 방지
- 잘못되거나 손상된 thumbnail 복구
- 처리 결과 및 오류를 로그 파일로 저장

### 요구 사항

- Windows
- Windows PowerShell 5.1 이상
- osu!stable
- `System.Drawing`을 사용할 수 있는 일반적인 Windows 환경

별도의 Python, Node.js 또는 외부 프로그램 설치는 필요하지 않습니다.

### 설치

다음 두 파일을 osu!stable 폴더에 넣습니다.

```text
osu!\
├── osu!.exe
├── cache.bat
├── cache.ps1
├── Songs\
└── Data\
    └── bt\
```

`cache.bat`을 사용하는 경우 BAT 파일과 PS1 파일은 **반드시 같은 폴더**에 있어야 합니다.

### 사용 방법

#### 1. osu!를 종료

thumbnail cache를 변경하기 전에 osu!stable을 종료하는 것을 권장합니다.

#### 2. BAT 실행

`cache.bat`을 더블 클릭합니다.

다음 메뉴가 표시됩니다.

```text
1 = Create missing thumbnails only
2 = Regenerate ALL thumbnails
3 = Create missing / repair invalid thumbnails
```

#### 3. 모드 선택

**1 - Create missing thumbnails only**

이미 `80×60`과 `160×120` thumbnail이 모두 정상적으로 존재하면 건너뜁니다.

처음 실행하거나 기존 cache를 최대한 유지하고 싶을 때 권장합니다.

**2 - Regenerate ALL thumbnails**

기존 thumbnail이 있어도 전부 다시 생성합니다.

배경 이미지가 변경되었거나 cache를 처음부터 다시 만들고 싶을 때 사용합니다.

**3 - Create missing / repair invalid thumbnails**

정상적인 thumbnail은 유지하고, 없는 thumbnail 또는 크기가 잘못된/읽을 수 없는 thumbnail을 다시 생성합니다.

일반적으로 **3번을 가장 추천합니다.**

### `BeatmapSetID:-1` 처리

일부 비공식/미완성/특수한 beatmap에는 다음처럼 SetID가 `-1`일 수 있습니다.

```text
Easy.osu       BeatmapSetID:-1
Normal.osu     BeatmapSetID:123456
Hard.osu       BeatmapSetID:123456
```

스크립트는 mapset 폴더의 모든 `.osu` 파일을 검사하여:

```text
BeatmapSetID:-1
        ↓
다른 난이도 확인
        ↓
BeatmapSetID:123456 발견
        ↓
123456.jpg
123456l.jpg
```

와 같이 처리합니다.

모든 난이도가 `-1`인 경우에는 임의의 ID를 생성하지 않습니다. 이런 mapset은 `ThumbnailGeneratorLogs`의 로그에 기록됩니다.

### Background 찾기

각 `.osu` 파일의 `[Events]` 섹션을 검사합니다.

예:

```text
[Events]
0,0,"background.jpg",0,0
```

그러면 mapset 폴더에서:

```text
background.jpg
```

를 찾습니다.

난이도가 여러 개라면 모든 `.osu` 파일을 검사하므로, 한 난이도의 SetID가 `-1`이어도 다른 난이도에서 정보를 가져올 수 있습니다.

### Thumbnail 크기

스크립트는 다음 크기로 생성합니다.

```text
Small:
80 × 60

Large:
160 × 120
```

둘 다 4:3 비율입니다.

원본 background가 16:9, 3:2 등의 다른 비율인 경우 중앙 부분을 crop하여 4:3으로 맞춘 후 thumbnail을 생성합니다.

### 로그

실행 후 osu! 폴더에 다음과 같은 폴더가 생성될 수 있습니다.

```text
ThumbnailGeneratorLogs\
├── summary_YYYYMMDD_HHMMSS.txt
├── thumbnail_failed_YYYYMMDD_HHMMSS.txt
├── minus_one_fixed_YYYYMMDD_HHMMSS.txt
├── setid_conflicts_YYYYMMDD_HHMMSS.txt
└── no_background_YYYYMMDD_HHMMSS.txt
```

특히 다음 파일을 확인하면 문제가 있는 mapset을 찾을 수 있습니다.

- `thumbnail_failed_...txt` → thumbnail 생성 실패
- `minus_one_fixed_...txt` → 다른 난이도에서 `-1` 대신 정상 SetID를 찾은 mapset
- `setid_conflicts_...txt` → 같은 폴더에서 서로 다른 정상 SetID가 발견된 경우
- `no_background_...txt` → 사용할 background를 찾지 못한 mapset

### 주의 사항

1. **실행 전에 osu!stable을 종료하는 것을 권장합니다.**
2. `Data\bt`를 직접 수정하는 프로그램이므로 중요한 cache가 있다면 백업하는 것이 좋습니다.
3. `BeatmapSetID`가 모든 난이도에서 `-1`인 mapset은 안전하게 처리할 수 없으므로 건너뜁니다.
4. WebP는 Windows `System.Drawing`에서 기본적으로 안정적인 지원이 보장되지 않으므로 현재 버전에서는 지원하지 않습니다.
5. 이 프로그램은 osu!stable의 thumbnail cache 규격에 맞춰 파일을 생성하지만, osu! 내부의 JPEG 인코딩 알고리즘과 **바이트 단위로 동일하다는 보장은 없습니다.**

### BAT 파일을 실행하지 않고 직접 실행

PowerShell에서 다음 명령으로 실행할 수도 있습니다.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File ".\cache.ps1"
```

PowerShell에서 실행 정책 때문에 막히는 경우에는 Windows의 보안 정책을 무리하게 변경하기보다 관리자/시스템 정책을 확인하세요.

---

## English

### Introduction

`cache.ps1` is a PowerShell script that bulk-generates the beatmap thumbnail cache used by **osu!stable** in `Data\bt`.

It scans your installed beatmaps under `Songs`, finds the background image referenced by the `.osu` files, and creates thumbnails for osu!stable.

Generated files:

```text
osu!\Data\bt\
├── 123456.jpg
└── 123456l.jpg
```

- `123456.jpg` → 80 × 60
- `123456l.jpg` → 160 × 120

### Features

- Recursively scans the `Songs` directory
- Checks **all `.osu` difficulties in each mapset folder**
- Resolves `BeatmapSetID:-1` by checking other difficulties in the same mapset
- Compares SetIDs found across difficulties
- Reads background references from the `.osu` `[Events]` section
- Supports JPG / JPEG / PNG / BMP / GIF / TIFF
- Crops backgrounds to a 4:3 aspect ratio
- Generates 80×60 and 160×120 JPEG thumbnails
- Skips valid existing thumbnails when appropriate
- Repairs missing or invalid thumbnails
- Writes detailed logs for failures and special cases

### Requirements

- Windows
- Windows PowerShell 5.1 or later
- osu!stable
- A normal Windows environment with `System.Drawing` available

No Python, Node.js, or other third-party runtime is required.

### Installation

Place these files directly in your osu!stable directory:

```text
osu!\
├── osu!.exe
├── cache.bat
├── cache.ps1
├── Songs\
└── Data\
    └── bt\
```

If you use `cache.bat`, the BAT and PS1 files must be in the **same directory**.

### How to Use

#### 1. Close osu!

It is recommended to completely close osu!stable before modifying the thumbnail cache.

#### 2. Run the BAT file

Double-click:

```text
cache.bat
```

You will see:

```text
1 = Create missing thumbnails only
2 = Regenerate ALL thumbnails
3 = Create missing / repair invalid thumbnails
```

#### 3. Select a mode

**1 - Create missing thumbnails only**

If both the 80×60 and 160×120 thumbnails already exist and are valid, they are skipped.

Recommended for a first run when you want to preserve existing cache files.

**2 - Regenerate ALL thumbnails**

Regenerates thumbnails even when valid cache files already exist.

Useful when backgrounds have changed or you want to rebuild the cache completely.

**3 - Create missing / repair invalid thumbnails**

Keeps valid thumbnails and regenerates missing, invalid, or unreadable thumbnails.

**Mode 3 is generally recommended.**

### Handling `BeatmapSetID:-1`

Some unofficial, incomplete, or special beatmaps may contain:

```text
Easy.osu       BeatmapSetID:-1
Normal.osu     BeatmapSetID:123456
Hard.osu       BeatmapSetID:123456
```

The script checks every `.osu` file in the mapset directory:

```text
BeatmapSetID:-1
        ↓
Check other difficulties
        ↓
Find BeatmapSetID:123456
        ↓
123456.jpg
123456l.jpg
```

If every difficulty has `BeatmapSetID:-1`, the script does **not** invent an ID. The mapset is skipped and recorded in the logs.

### Background Detection

The script reads the `[Events]` section of each `.osu` file.

For example:

```text
[Events]
0,0,"background.jpg",0,0
```

The script then searches for:

```text
background.jpg
```

inside the mapset directory.

Because every `.osu` file is checked, a valid background can still be found even if another difficulty is incomplete or has `BeatmapSetID:-1`.

### Thumbnail Sizes

The script generates:

```text
Small:
80 × 60

Large:
160 × 120
```

Both use a 4:3 aspect ratio.

If the source background uses another aspect ratio, such as 16:9 or 3:2, the script center-crops it to 4:3 before resizing.

### Logs

A log directory may be created inside the osu! directory:

```text
ThumbnailGeneratorLogs\
├── summary_YYYYMMDD_HHMMSS.txt
├── thumbnail_failed_YYYYMMDD_HHMMSS.txt
├── minus_one_fixed_YYYYMMDD_HHMMSS.txt
├── setid_conflicts_YYYYMMDD_HHMMSS.txt
└── no_background_YYYYMMDD_HHMMSS.txt
```

Useful logs include:

- `thumbnail_failed_...txt` → thumbnail generation failures
- `minus_one_fixed_...txt` → mapsets where a valid SetID was recovered from another difficulty
- `setid_conflicts_...txt` → multiple different valid SetIDs were found in one folder
- `no_background_...txt` → no usable background could be found

### Important Notes

1. **Close osu!stable before running the generator.**
2. Since the script modifies `Data\bt`, backing up important cache files is recommended.
3. Mapsets where every difficulty has `BeatmapSetID:-1` are skipped because there is no safe filename to use.
4. WebP is not included in the current version because reliable WebP support is not guaranteed by Windows `System.Drawing`.
5. The generated files follow the expected osu!stable thumbnail dimensions and naming convention, but the script does **not guarantee byte-for-byte identical JPEG encoding** to osu!stable's internal thumbnail generator.

### Running Without the BAT File

You can also run the PowerShell script directly:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File ".\cache.ps1"
```

If PowerShell execution is blocked by a system execution policy, check your Windows/system policy rather than unnecessarily changing global security settings.

---

## File Layout

A complete installation should look like this:

```text
osu!\
│
├── osu!.exe
├── cache.bat
├── cache.ps1
│
├── Songs\
│   ├── Mapset 1\
│   │   ├── Easy.osu
│   │   ├── Hard.osu
│   │   └── background.jpg
│   │
│   └── Mapset 2\
│       ├── Normal.osu
│       └── background.png
│
├── Data\
│   └── bt\
│       ├── 123456.jpg
│       ├── 123456l.jpg
│       └── ...
│
└── ThumbnailGeneratorLogs\
    └── ...
```

## License / Disclaimer

This is a community utility intended for use with osu!stable's local beatmap thumbnail cache.

It is not an official osu! or ppy tool.
