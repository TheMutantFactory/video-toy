# Video Toy cue sheet — the first minute of a set. Times are seconds from
# the start, or bars / beats at the running clock's tempo (120 bpm without one).
# Commands are the learn table's actions and params (docs/controllers/osc-addresses.txt).

0:00      note "opener"
0:00      action preset_1
0:00      action feedback
0:02      param fb_fade 0.6 over 6s
bar 4     action spawn
bar 4     action spawn
+1 bar    action spawn
bar 8     param fb_zoom 0.75 over 4 bars
bar 12    action next_palette
bar 16    action surprise
bar 24    action glow
bar 28    param fb_twist 0.7 over 2 bars
bar 32    action panic
+2        note "end of the opener"
