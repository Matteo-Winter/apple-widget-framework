# Physical iPhone lab — falsifiable experiment plan

**Goal:** measure whether a single existing home-screen widget can represent many agent-defined UIs with useful refresh and response times, using supported iOS capabilities.

## Experimental environment
- Physical iPhone + exact iOS version: **TBD**
- Mac / Xcode version: **TBD**
- Developer Mode (on/off): **record**
- Widget size: **small and medium, start with medium**
- App bundle and App Group: **replace example IDs for own signing team**
- Record whether app was foreground/background/terminated and screen was locked/unlocked

## H0 / H1
H0: A widget's layout can change only when its compiled view is updated.  
H1: A widget's **precompiled component renderer** can display substantially different externally-defined layouts without installing a new widget (but only when iOS refreshes it).

H0: Data changed in shared storage produces immediate visibility.  
H1: Shared data mutation alone is insufficient; refresh trigger and system scheduling matter.

## Experiments
| ID | Manipulation | Measurement | What falsifies proposed advantage |
| --- | --- | --- | --- |
| E01 | In-app publish JSON status/choice/result and call WidgetCenter reload | Layout differs without reinstall; time to visible change | Layout cannot change with same bundle |
| E02 | Write JSON without reload, app sent to background | Does UI spontaneously change? (should not be assumed) | Unreliable/absent refresh documented |
| E03 | Tap native widget Button that executes AppIntent and writes new state | User tap -> UI change delay; app not opened | Unexpected app launch, stale UI |
| E04 | Timeline schedule known next state | Planned display delay vs expected timestamp | Excessive drift/unreliable change |
| E05 | Enter invalid/oversized JSON, stale versions | No crash, safe fallback | Crash, misleading UI |
| E06 | Tap two different responses quickly / replay old request | At most one accepted action | Duplicate or stale approval |
| E07 | Local Live Activity then background / lock test | Content update visibility and lifecycle | Unreliable/lifecycle limits |
| E08 | WidgetKit APNs push (future integration) | Push send -> displayed update distribution | Delays/budgets defeat use case |
| E09 | Multiple agents/content updates under load | Loss, reordering, battery and visibility | Unacceptable stale state |

## How to record
Create one markdown test record per real run under `experiments/results/YYYY-MM-DD-E##.md`, including:
- OS/Xcode/device details and exact code commit
- Build/sign/install evidence
- Start/end UTC timestamps and observed latency
- Screenshot or screen recording identifier
- Test setup (network, app state, display, Developer Mode)
- Pass/Fail/Limitations; never infer a pass from simulator alone

## Decision gates
**G0:** Swift code can compile on supported Xcode and install.  
**G1:** One fixed widget renders status, choice, result as separate layouts.  
**G2:** User-triggered native response updates state without opening the main app.  
**G3:** Background/external updates show a repeatable acceptable latency distribution.  
**G4:** No unsafe code execution / unsupported background modes needed.

**Stop / rethink:** if the essential UX requires persistent sub-second arbitrary content streaming with the phone locked, WidgetKit alone should not be used for that requirement.
