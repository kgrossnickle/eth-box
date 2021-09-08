# Xbox Ethereum Miner
[miner-screepshot](img/miner-screenshot.png)
## Current State
~3 MH/s on Xbox Series S. Feasible to get 5 MH/s with minor changes to current code. With major changes to HLSL code, 15-20MHS *should* be possible, but needs a Shader code wizard
Unknown MH/s On Series X / Xbox One

** Note
The 3 MH/s is closer to 1.5 MH/s for most pools due to bug #1 (bondary condition) in the bugs section.  If your pool uses a boundary stricter than 00000000XXXXXXXXXXXXX then its fine

## Thanks
HLSL based upon code from:
https://github.com/gyf304/ethash-hlsl
with some bug fixes
# Building/Running on PC
## Prereqs
Win 10  
Visual Studio 2019   
VS C++ and WinRT packages ( should ask if you want to install these after git cloning)  
Xbox Series S, Series X or Xbox One. (Might work with others? :shrug:	)
## Other packages needed
1.  You need to install boost with WinRT / uwp bindings and add to Visual Studio path.
 I used vcpkg to install boost to C:\dev and so if your install location isnt C:\dev\vcpkg\installed\x64-uwp\include then you will need to change in _properties -> C/C++ -> additional include dirs_
 and if the libraries arent in C:\dev\vcpkg\installed\x64-uwp\lib to then change _properties -> linker -> additional lib dirs_
2. I added prebuilt libraries of ethash (https://github.com/chfast/ethash) , if you have trouble you may need to build this yourself with WinRT bindings. Good luck, its a pain in the booty. If you do need this the process would be git clone -> follow their build directions and change cmake command to output as winrt. Then change properties -> linker -> additinal libs to point to there instead of the ones I added. IDK if this is needed since I did the grunt work.
## Building REALLY Important Notes
1. This can only build in debug X64 mode right now. Probably trivial to make othermodes work, except you also need to rebuild ethash in release etc. mode.

if you have any problems make an issue and I'll try to help
# Running on Xbox
First you will need a Microsoft Developer account to use dev mode on your Xbox. Unfortunately... this used to cost $10 and now costs $19. Really dumb IMO.
Then you will need to put your Xbox in developer mode.
This article covers the above 2 steps well.
https://www.howtogeek.com/703443/how-to-put-your-xbox-series-x-or-s-into-developer-mode/

Then you will need to connect via WIFI or build the appx package and put on xbox. This doc covers it well
https://docs.microsoft.com/en-us/windows/uwp/xbox-apps/development-environment-setup
# Change Wallet & Choosing Pool 
Edit ```std::string wallet = "0x53C58a76a9E702efC8298E7F29f322Cd2e59847E";``` ~ line 9 of MainPage.cpp to your wallet

Change pool by commenting out  ```iResult = getaddrinfo("us1.ethpool.org", "3333", &hints, &result);``` ~ line 112 in ```start_sock()``` in MainPage.cpp and uncomment the pool you want to try or find their URL/ Port etc. Most of the pools commented out should work when uncommented but I dont remember, because some don't ( and some like nanopool have a very high boundary which is almost unusable at 3 MH/s.

# Bugs
1.The Bound for the miner is a hash that begins with 00000000XXXXXXXXXXXXX (8 preceding 0s example: 00000000b9de3b6e15924387fde5fa0a13a2fb4725a30ffbb597e4721da28f36). However, most pools have a less strict hash than this so you will miss out on blocks _significantly_ hurting your return from the pool. The fix is to add a boundary checker to ETHashMine.hlsl ~ line 469. Currently it is
 ```if (concat[0].x == 0) {```
 where concat[0] stores the 8 first digits, so only if there all zero do we report a solution.
 this _should_ be
 ```if (concat[0].x < boundary)```
 but since concat is in little endian this is actually super non-trivial (at least to me. Its probably trivial to some bit master).
 
 2. Some epochs are 50x slower... NO idea why. Probably some error in the HLSL code, which on error GPU code takes the maximum path to return which could be 50x slower. An example error epoch is epoch 435 (seed = 37f0818a24a483c5bd9c28e7b455358ccfe14a11e3504f5290946f9e3582775c ). On my 2070 RTX , I get 17 MH/s on epoch 434 and 436 and **.32** MH/s on epoch 435, around 50x slower... 
# Change GPU to run on ( for CPU testing )
in ```MainPage::MainPage()``` change ```miner = DXMiner(0); ``` to ```miner = DXMiner(YOUR_GPU_OR_CPU_NUM)``` where the number is the index number from the dropdown from the device tab from the GUI when you run it. Sorry I hardcoded this for SPEEEDDDDD and since GPU is always index 0 so it should only cause trouble if you have more than 1
# Testing
Open Mainpage.cpp
 and comment out or uncomment 
 miner.set_test_vars();
 miner.mine_forever();
 in  ```MainPage::MainPage()``` function to change the miner to run on test data so you can test speed, vs actually connect to a pool and mine.
 These lines make the miner mine forever before even showing the GUI, so you cant test speed changes without even loading the GUI.
 
 # How to improve / make feasible
 If you edit the HLSL shader code in ETHash.hlsi, ETHashGenerateDataset.hlsl and ETHashMine.hlsl you should be able to get speed improvements if your a better graphics programmer than I am. The real key is to debug what is going on in the xbox (GPU usage) which is locked to Xbox Creator program members. If you could see where the shader code is inefficient (ex. is it inefficient in UAV memory vs SRV memory vs thread size vs warp size) then update to meet max GPU performance
