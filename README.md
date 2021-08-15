# Xbox Ethereum Miner


# Bugs
The Bound for the miner is a hash that begins with 00000000XXXXXXXXXXXXX (8 preceding 0s example: 00000000b9de3b6e15924387fde5fa0a13a2fb4725a30ffbb597e4721da28f36). However, most pools have a less strict hash than this so you will miss out on blocks _significantly_ hurting your return from the pool. The fix is to add a boundary checker to ETHashMine.hlsl ~ line 469. Currently it is
 ```if (concat[0].x == 0) {```
 where concat[0] stores the 8 first digits, so only if there all zero do we report a solution.
 this _should_ be
 ```if (concat[0].x < boundary)```
 but since concat is in little endian this is actually super non-trivial (at least to me. Its probably trivial to some bit master).
# Change GPU run on
in ```MainPage::MainPage()``` change ```miner = DXMiner(0); ``` to ```miner = DXMiner(YOUR_GPU_OR_CPU_NUM)``` where the number is the index number from the dropdown. Sorry I hardcoded this for SPEEEDDDDD and since GPU is always index 0 if yours is recognized
# Testing
Open Mainpage.cpp
 and comment out or uncomment 
 miner.set_test_vars();
 miner.mine_forever();
 in  MainPage::MainPage() function to change the miner to run on test data so you can test speed, vs actually connect to a pool and mine.
 These lines make the miner mine forever before even showing the GUI, so you cant test speed changes without even loading the GUI.
