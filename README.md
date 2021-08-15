# Xbox Ethereum Miner
# Running
## Prereqs
Win 10
Visual Studio 2019
C++ and WinRT packages ( should ask if you want to install these after git cloning)
## Other packages needed
1.  You need to install boost with WinRT / uwp bindings and add to Visual Studio path.
 I used vcpkg to install boost to C:\dev and so if your install location isnt C:\dev\vcpkg\installed\x64-uwp\include then you will need to change in _properties -> C/C++ -> additional include dirs_
 and if the libraries arent in C:\dev\vcpkg\installed\x64-uwp\lib to then change _properties -> linker -> additional lib dirs_
2. I added prebuilt libraries of ethash (https://github.com/chfast/ethash) , if you have trouble you may need to build this yourself with WinRT bindings. Good luck, its a pain in the booty. If you do need this the process would be git clone -> follow their build directions and change cmake command to output as winrt. Then change properties -> linker -> additinal libs to point to there instead of the ones I added. IDK if this is needed since I did the grunt work.

# Bugs
The Bound for the miner is a hash that begins with 00000000XXXXXXXXXXXXX (8 preceding 0s example: 00000000b9de3b6e15924387fde5fa0a13a2fb4725a30ffbb597e4721da28f36). However, most pools have a less strict hash than this so you will miss out on blocks _significantly_ hurting your return from the pool. The fix is to add a boundary checker to ETHashMine.hlsl ~ line 469. Currently it is
 ```if (concat[0].x == 0) {```
 where concat[0] stores the 8 first digits, so only if there all zero do we report a solution.
 this _should_ be
 ```if (concat[0].x < boundary)```
 but since concat is in little endian this is actually super non-trivial (at least to me. Its probably trivial to some bit master).
# Change GPU to run on
in ```MainPage::MainPage()``` change ```miner = DXMiner(0); ``` to ```miner = DXMiner(YOUR_GPU_OR_CPU_NUM)``` where the number is the index number from the dropdown. Sorry I hardcoded this for SPEEEDDDDD and since GPU is always index 0 if yours is recognized
# Testing
Open Mainpage.cpp
 and comment out or uncomment 
 miner.set_test_vars();
 miner.mine_forever();
 in  MainPage::MainPage() function to change the miner to run on test data so you can test speed, vs actually connect to a pool and mine.
 These lines make the miner mine forever before even showing the GUI, so you cant test speed changes without even loading the GUI.
https://github.com/chfast/ethash
