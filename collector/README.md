# Feed collector

Records both live feeds around the clock, so arrival predictions can be trained on real data later. The app's own predictions come from ETA Spot and are often off; the plan is to learn how long each stretch between two stops really takes, by route, time of day and day of week.

`collect.py` keeps everything the feeds say, raw, so any later model can be built from it without collecting again:

| What | How often | Where |
| --- | --- | --- |
| Every bus: position, last and next stop, the feed's short-range predictions, crowding, schedule | 15 s | `data/YYYY-MM-DD/HH-vehicles.jsonl.xz` |
| Every stop's predicted arrivals | 60 s | `data/YYYY-MM-DD/HH-etas.jsonl.xz` |
| Routes, stops, patterns (only when they change) | 6 h | `data/static/` |
| Each time a bus leaves a stop | as it happens | `events/YYYY-MM-DD-left-stop.jsonl.gz` |

The last one is the ground truth that predictions get graded against, and the only part that can't be rebuilt later, so it's kept even when raw data stops: raw snapshots stop being saved once `data/` reaches `BTOWN_BUDGET_GB` (2 by default), to stay inside a home-folder quota.

Standard library only (Python 3.9+). Times in folder and file names are Bloomington local time.

## Running it

```sh
python3 collect.py --once   # one round, to check it works
python3 collect.py          # runs until killed; a second copy exits at once
```

On the server it runs from cron, which also restarts it if it dies:

```
*/5 * * * * cd $HOME/btown-bus-collector && /usr/bin/python3 collect.py >> collector.log 2>&1
@reboot cd $HOME/btown-bus-collector && /usr/bin/python3 collect.py >> collector.log 2>&1
```

`collector.log` gets a line per feed failure and an hourly count of what was saved. Settings: `BTOWN_DATA`, `BTOWN_EVENTS`, `BTOWN_BUDGET_GB`.

To update the server copy: `scp collector/collect.py ash:btown-bus-collector/`, then `pkill -f "python3 collect.py"`; cron starts the new version within 5 minutes.
