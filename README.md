# Xbox Ethereum Miner

# Testing
Open Mainpage.cpp
 and comment out or uncomment 
 miner.set_test_vars();
 miner.mine_forever();
 in  MainPage::MainPage() function to change the miner to run on test data so you can test speed, vs actually connect to a pool and mine.
 These lines make the miner mine forever before even showing the GUI, so you cant test speed changes without even loading the GUI.
