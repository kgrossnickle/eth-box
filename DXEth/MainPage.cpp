#include "pch.h"
#include "MainPage.h"
#include "MainPage.g.cpp"

#include <codecvt>
#include "DXMiner.h"
#include "Constants.h"
#include "json.hpp"

// for convenience
using json = nlohmann::json;


using namespace winrt;
using namespace Windows::UI::Core;
using namespace Windows::UI::Popups;
using namespace Windows::UI::Xaml;
using namespace Windows::Foundation;

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdlib.h>
#include <stdio.h>


// Need to link with Ws2_32.lib, Mswsock.lib, and Advapi32.lib
#pragma comment (lib, "Ws2_32.lib")
#pragma comment (lib, "Mswsock.lib")
#pragma comment (lib, "AdvApi32.lib")


#define DEFAULT_BUFLEN 1024
#define DEFAULT_PORT "9997" //"53817"

std::wstring s2ws2(const std::string& str)
{
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

int send_msg(std::string msg_name, std::string msg_val, SOCKET ConnectSocket) {
    OutputDebugString(L"\nin send msg func");
    int iResult;
    const char* sendbuf = "";
    if (msg_name == "subscribe") {
        sendbuf = "{\"id\": 1,\"method\" : \"mining.subscribe\",\"params\" : [\"DebugKMine/1.0.0\", \"EthereumStratum/1.0.0\" ]}\n ";
    }
    else if (msg_name == "auth") {
        sendbuf = "{\"id\": 2,\"method\" : \"mining.authorize\",\"params\" : [\"0x53C58a76a9E702efC8298E7F29f322Cd2e59847E\",\"\"]}";
    }
    else if (msg_name == "auth2") {
        sendbuf = "{\"id\":1,\"method\":\"eth_submitLogin\",\"params\":[\"0x53C58a76a9E702efC8298E7F29f322Cd2e59847E\",\"X\"],\"worker\":\"KMine\"}\n";
    }
    else if (msg_name == "submit") {
        sendbuf = msg_val.c_str();
    }
    else if (msg_name == "getwork") {
        sendbuf = "{\"id\":5,\"method\":\"eth_getWork\",\"params\":[]}\n";
    }
    // Send an initial buffer
    std::string s_buf(sendbuf);
    OutputDebugString(s2ws2(s_buf).c_str());

    iResult = send(ConnectSocket, sendbuf, (int)strlen(sendbuf), 0);
    if (iResult == SOCKET_ERROR) {
        OutputDebugString(L"send failure");
        printf("send failed with error: %d\n", WSAGetLastError());
        closesocket(ConnectSocket);
        WSACleanup();
        return -1;
    }
    OutputDebugString(L"\nsent bytes\n");
    //printf("Bytes Sent: %ld\n", iResult);
    return 0;
}
SOCKET start_sock() {
    WSADATA wsaData;
    SOCKET ConnectSocket = INVALID_SOCKET;
    struct addrinfo* result = NULL,
        * ptr = NULL,
        hints;
    char recvbuf[DEFAULT_BUFLEN];
    int iResult;
    int recvbuflen = DEFAULT_BUFLEN;


    // Initialize Winsock
    iResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
    if (iResult != 0) {
        printf("WSAStartup failed with error: %d\n", iResult);
        return NULL;
    }

    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    // Resolve the server address and port
    //iResult = getaddrinfo("localhost", DEFAULT_PORT, &hints, &result);
    //iResult = getaddrinfo("stratum1+tcp://0x53C58a76a9E702efC8298E7F29f322Cd2e59847E.workertest@eth-us-east1.nanopool.org", "9999", &hints, &result);
    // BELOW WORKS! but not 100% bc auth
    //iResult = getaddrinfo("eth-us-east1.nanopool.org", "9999", &hints, &result);
    iResult = getaddrinfo("us1.ethpool.org", "3333", &hints, &result);
    //iResult = getaddrinfo("us1.ethermine.org", "4444", &hints, &result);
    //iResult = getaddrinfo("eth.2miners.com", "2020", &hints, &result);
    //iResult = getaddrinfo("0x53C58a76a9E702efC8298E7F29f322Cd2e59847E.workertest@eth-us-east1.nanopool.org", "9999", &hints, &result);
    if (iResult != 0) {
        printf("getaddrinfo failed with error: %d\n", iResult);
        OutputDebugString(L"\n\n\ngetaddrinfo failed in socket call with error code:\n");
        OutputDebugString(to_wstring(iResult).c_str());
        OutputDebugString(L"\n\n\n\n\n\n\n\n");
        WSACleanup();
        return INVALID_SOCKET;
    }

    // Attempt to connect to an address until one succeeds
    for (ptr = result; ptr != NULL; ptr = ptr->ai_next) {

        // Create a SOCKET for connecting to server
        ConnectSocket = socket(ptr->ai_family, ptr->ai_socktype,
            ptr->ai_protocol);
        if (ConnectSocket == INVALID_SOCKET) {
            printf("socket failed with error: %ld\n", WSAGetLastError());
            OutputDebugString(L"\n\n\ntcp socket failed in socket call with error code:\n");
            OutputDebugString(to_wstring(WSAGetLastError()).c_str());
            OutputDebugString(L"\n\n\n\n\n\n\n\n");
            WSACleanup();
            return INVALID_SOCKET;
        }

        // Connect to server.
        iResult = connect(ConnectSocket, ptr->ai_addr, (int)ptr->ai_addrlen);
        if (iResult == SOCKET_ERROR) {
            closesocket(ConnectSocket);
            ConnectSocket = INVALID_SOCKET;
            OutputDebugString(L"\n\n\ntcp socket failed in connect call\n");
            continue;
        }
        break;
    }

    freeaddrinfo(result);

    if (ConnectSocket == INVALID_SOCKET) {
        OutputDebugString(L"Unable to connect to server!\n");
        WSACleanup();
        return INVALID_SOCKET;
    }



    // shutdown the connection since no more data will be sent
    //iResult = shutdown(ConnectSocket, SD_SEND);
    //if (iResult == SOCKET_ERROR) {
    //    printf("shutdown failed with error: %d\n", WSAGetLastError());
    //    closesocket(ConnectSocket);
    //    WSACleanup();
    //    return INVALID_SOCKET;
    //}

    int login_ok = send_msg("auth2", "", ConnectSocket);
    int getwork_ok = send_msg("getwork", "", ConnectSocket);
    if (login_ok != 0) {
        OutputDebugString(L"\n\nUnable to send login message!\n\n");
    }
    if (getwork_ok != 0) {
        OutputDebugString(L"\n\nUnable to send getwork message!\n\n");
    }

    return ConnectSocket;
    // Receive until the peer closes the connection
}

using namespace Concurrency;
using namespace Windows::ApplicationModel::Core;
using namespace Windows::Foundation;
using namespace Windows::Networking::Sockets;
using namespace Windows::UI::Core;
using namespace Windows::UI::Xaml;
using namespace Windows::UI::Xaml::Controls;
using namespace Windows::UI::Xaml::Navigation;

namespace winrt::DXEth::implementation




{
    winrt::DXEth::DXMiner miner;

    std::wstring s2ws(const std::string& str)
    {
        int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
        std::wstring wstrTo(size_needed, 0);
        MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
        return wstrTo;
    }


    MainPage::MainPage()
    {
        auto deviceList = DXMiner::listDevices();
        std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>, wchar_t> wcharConv;
        InitializeComponent();
        for (auto& device : deviceList) {
            devicesComboBox().Items().Append(PropertyValue::CreateString(wcharConv.from_bytes(device)));
        }

        auto x = constants.GetCacheSize(0);
        miner = DXMiner(0);
        //miner.set_test_vars();
        //miner.mine_forever();
        //miner.set_test_vars();
        //miner.mine_forever();
        
    }

    int32_t MainPage::MyProperty()
    {
        throw hresult_not_implemented();
    }

    void MainPage::MyProperty(int32_t /* value */)
    {
        throw hresult_not_implemented();
    }

    void start_mining() {
        //miner.mine_once();
        miner.mine_forever();
    }
    std::string remove_quotes(std::string s) {
        s.erase(remove(s.begin(), s.end(), '\"'),s.end());
        return s;
    }

    std::string ReplaceString(std::string subject, const std::string& search,
        const std::string& replace) {
        size_t pos = 0;
        while ((pos = subject.find(search, pos)) != std::string::npos) {
            subject.replace(pos, search.length(), replace);
            pos += replace.length();
        }
        return subject;
    }

    void stratum_loop(SOCKET ConnectSocket) {
        int iResult = 1;//WSAStartup(MAKEWORD(2, 2), &wsaData);
        char recvbuf[DEFAULT_BUFLEN];
        int recvbuflen = DEFAULT_BUFLEN;
        do {
            while (miner.solutions.size() > 0) {
                OutputDebugString(L"\n\nSending solution message!!!\n\n ");
                solution sol = miner.solutions.back();
                miner.solutions.pop_back();
                std::string wallet = "0x53C58a76a9E702efC8298E7F29f322Cd2e59847E";
                //std::string submitMsg = "{\"id\": 3,  \"method\" : \"mining.submit\",\"params\" : [\""+ wallet +"\",\""+job_id+"\",\""+ nonce_wo_extra +"\"]}";
                std::string submitMsg = "{ \"id\":3,\"method\" : \"eth_submitWork\",\"params\" : [\"0x" + sol.nonce + "\",\"0x" + sol.header + "\",\"0x" + sol.mix + "\"] ,\"worker\" : \"KMine\" }\n";
                OutputDebugString(L"\n\n solution message is: \n\n ");
                OutputDebugString(s2ws(submitMsg).c_str());
                OutputDebugString(L"\n\n calling send msg\n\n ");
                send_msg("submit", submitMsg, ConnectSocket);
            }
            //std::this_thread::sleep_for(std::chrono::milliseconds(250));
            iResult = recv(ConnectSocket, recvbuf, recvbuflen, 0);
            //ignore long messages / blasted messages
            if (iResult > 1 && iResult < DEFAULT_BUFLEN) {
                printf("Bytes received: %d\n", iResult);
                recvbuf[iResult] = '\0';
                std::string rec_str(recvbuf);
                //only print messages before we start
                if (miner.need_stop == true) {
                    OutputDebugString(L"\n\ngot message:\n\n ");
                    OutputDebugString(s2ws(rec_str).c_str());
                }
                rec_str = "[" + ReplaceString(rec_str, "}{", "},{") + "]";
                rec_str = ReplaceString(rec_str, "}\r\n{", "},{");
                rec_str = ReplaceString(rec_str, "} \r\n{", "},{");
                rec_str = ReplaceString(rec_str, "} \n{", "},{");
                rec_str = ReplaceString(rec_str, "}\n{", "},{");
                if (miner.need_stop == true) {
                    OutputDebugString(L"\n Formatted message:\n ");
                    OutputDebugString(s2ws(rec_str).c_str());
                    OutputDebugString(L"\n");
                }
                int num_msgs = 0;  
                json all_js;
                try {
                    all_js = json::parse(rec_str);
                    num_msgs = all_js.size();
                }
                catch (...) {
                    OutputDebugString(L"\n Badly formatted msg. Probably got messed up during DAG creation\n ");
                }
                /*for (auto& [key, val] : js.items())
                {
                    std::string skey(key);
                    std::string sval = val.dump();
                    OutputDebugString(L"\nkey: ");
                    OutputDebugString(s2ws(skey).c_str()); //<< ", value:" << val << '\n';
                    OutputDebugString(L"\nval: ");
                    OutputDebugString(s2ws(sval).c_str());
                }*/
                for (int i = 0; i < num_msgs; i++) {
                    json js = all_js[i];
                    std::string msg_id = js["id"].dump();
                    //OutputDebugString(L"rec msg");
                    //OutputDebugString(L"\n msg id is: \n");
                    //OutputDebugString(s2ws(msg_id).c_str());
                    //OutputDebugString(L"\n");
                    if (msg_id == "1") {
                        if (!js.contains("result") || js["result"].dump() != "true") {
                            OutputDebugString(L"\nERROR AUTHING got error code from pool: \n");
                            OutputDebugString(s2ws(js["result"].dump()).c_str());
                        }

                        OutputDebugString(L"\n\nfull auth resp message:\n\n ");
                        OutputDebugString(s2ws(js.dump()).c_str());
                        miner.m_extra_nonce_str = "3dea";
                        miner.set_cur_nonce_from_extra_nonce();
                        miner.has_extra_nonce = true;
                        /*
                        if (js["error"].dump() != "null") {
                            OutputDebugString(L"\nERROR CONNECTING got error code from pool: \n");
                            OutputDebugString(s2ws(js["error"].dump()).c_str());
                        }
                        miner.m_extra_nonce_str = remove_quotes(js["result"][1].dump());
                        miner.set_cur_nonce_from_extra_nonce();
                        miner.m_stratum_id = remove_quotes(js["result"][0][1].dump());
                        //std::string msg_type = js["result"][0][0].dump();
                        OutputDebugString(L"\n\nfull subscribe resp message:\n\n ");
                        OutputDebugString(s2ws(js.dump()).c_str());
                        miner.has_extra_nonce = true;
                        //dont auth here anymore start with auth
                        //send_msg("auth2", "", ConnectSocket);
                        
                        if (miner.has_block_info == true && miner.has_boundary) {
                            miner.need_stop = false;
                        }*/
                    }

                    else if (msg_id == "2") {
                        //if (js["error"].dump() != "null") {
                        //    OutputDebugString(L"\nERROR AUTHING got error code from pool: \n");
                        //    OutputDebugString(s2ws(js["error"].dump()).c_str());
                        //}
                        if (!js.contains("result") || js["result"].dump() != "true" ) {
                            OutputDebugString(L"\nERROR AUTHING got error code from pool: \n");
                            OutputDebugString(s2ws(js["result"].dump()).c_str());
                        }
                        
                        OutputDebugString(L"\n\nfull auth resp message:\n\n ");
                        OutputDebugString(s2ws(js.dump()).c_str());
                    }
                    else if (msg_id == "3") {
                        OutputDebugString(L"\n\n\n\n\n\n\nGot share validity response!!!!!!:\n\n\n\n\n\n\n\n ");
                        OutputDebugString(s2ws(js.dump()).c_str());
                        OutputDebugString(L"\n\n\n\n");
                    }
                    else if (msg_id == "null" && js.contains("method")) {
                        std::string method = remove_quotes(js["method"].dump());
                        // we need to read message id = 1 to get extra nonce before starting to mine
                        if (method == "mining.notify" && miner.has_extra_nonce) {
                            //OutputDebugString(L"\n\nfull mining.notify message:\n\n ");
                            //OutputDebugString(s2ws(js.dump()).c_str());
                            miner.m_job_id = remove_quotes(js["params"][0].dump());
                            //OutputDebugString(L"\njob_id\n ");
                            //OutputDebugString(s2ws(miner.m_job_id).c_str());
                            miner.m_header_hash = remove_quotes(js["params"][2].dump());
                            //OutputDebugString(L"\nheader_hash\n ");
                            //OutputDebugString(s2ws(miner.m_header_hash).c_str());
                            miner.set_h256_header();
                            //OutputDebugString(L"\nblock_num : \n ");
                            
                            //miner.m_block_num = std::stoi(remove_quotes(js["height"].dump()));
                            
                            //OutputDebugString(std::to_wstring(miner.m_block_num).c_str());
                            //OutputDebugString(L"\nmsg seed : \n ");
                            std::string msgseed = remove_quotes(js["params"][1].dump());
                            //OutputDebugString(s2ws(msgseed).c_str());
                            //OutputDebugString(L"\n");
                            if (miner.m_seed != msgseed) {
                                //New Epoch!
                                miner.m_seed = msgseed;
                                OutputDebugString(L"\nPreparing DAG for epoch!\n");
                                miner.need_stop = true;
                                miner.prepareEpoch();
                                miner.has_block_info = true;
                                OutputDebugString(L"\nFinished DAG generation\n");
                                //after epoch we are ready to mine
                                //technically dont need boundary...
                                if (miner.has_extra_nonce == true){// && miner.has_boundary) {
                                    miner.need_stop = false;
                                }
                            }
                        }
                        else if (method == "mining.set_difficulty") {
                            OutputDebugString(L"\n\nfull set_difficulty message:\n\n ");
                            OutputDebugString(s2ws(js.dump()).c_str());
                            double diff = std::stod(remove_quotes(js["params"][0].dump()));
                            miner.m_difficulty_as_dbl = diff;
                            OutputDebugString(L"\n\nDifficulty as double:\n\n ");
                            OutputDebugString(std::to_wstring(miner.m_difficulty_as_dbl).c_str());
                            OutputDebugString(L"\n");
                            //miner.set_boundary_from_diff();
                            //this is diff 1 
                            // HARDCODED !!!!!!!!!!!!!!!!!!!      
                            //miner.set_debug_boundary_from_hash_str("00000000ffff0000000000000000000000000000000000000000000000000000");
                            miner.set_debug_boundary_from_hash_str("0x00001c01710000000000000000000000d1ff1c01710000000000000000000000");
                            miner.has_boundary = true;
                            //if we set epoch then get difficulty message
                            if (miner.has_block_info == true && miner.has_extra_nonce) {
                                miner.need_stop = false;
                            }
                        }
                        else {
                            OutputDebugString(L"\n\nUNKOWN MSG TYPE with null id!!!!!\n\n ");
                            OutputDebugString(s2ws(js.dump()).c_str());
                            OutputDebugString(L"\n\n ");
                        }
                    }
                    else if (msg_id == "0") {
                        miner.m_header_hash = remove_quotes(js["result"][0].dump());
                        //OutputDebugString(L"\nheader_hash\n ");
                        //OutputDebugString(s2ws(miner.m_header_hash).c_str());
                        miner.set_h256_header();
                        //OutputDebugString(L"\nblock_num : \n ");

                        //miner.m_block_num = std::stoi(remove_quotes(js["height"].dump()));

                        //OutputDebugString(std::to_wstring(miner.m_block_num).c_str());
                        //OutputDebugString(L"\nmsg seed : \n ");
                        std::string msgseed = remove_quotes(js["result"][1].dump());
                        if (msgseed.substr(0,2) == "0x") {
                            msgseed = msgseed.substr(2);
                        }
                        //OutputDebugString(s2ws(msgseed).c_str());
                        std::string bound = remove_quotes(js["result"][2].dump());
                        //
                        // NOT USED YET, NEED TO FIX CURRENT IMPLEMENT in HLSL of simply needing 00000000
                        //
                        //OutputDebugString(L"\n");
                        if (miner.m_seed != msgseed) {
                            //New Epoch!
                            miner.m_seed = msgseed;
                            OutputDebugString(L"\nPreparing DAG for epoch!\n");
                            miner.need_stop = true;
                            miner.prepareEpoch();
                            miner.has_block_info = true;
                            OutputDebugString(L"\nFinished DAG generation\n");
                            //after epoch we are ready to mine
                            //technically dont need boundary...
                            if (miner.has_extra_nonce == true) {// && miner.has_boundary) {
                                miner.need_stop = false;
                            }
                        }
                    }
                    else {
                        OutputDebugString(L"\n\nUNKOWN MSG id!!!!!\n\n ");
                        OutputDebugString(s2ws(js.dump()).c_str());
                        OutputDebugString(L"\n\n ");
                    }
                }


            }
            else {
                if (iResult == 0) {
                        OutputDebugString(L"Connection closed\n");
                }
                OutputDebugString(L"recv failed with error code:\n");
                OutputDebugString(to_wstring(WSAGetLastError()).c_str() );
                OutputDebugString(L"\n\n\n\n***RECONNECTING****\n\n\n\n");
                ConnectSocket = start_sock();
            }

        } while (iResult > 0);
    }
    void main_loop() {
        SOCKET ConnectSocket = start_sock();

        //Receive messages on socket in seperate thread
        std::thread t1(stratum_loop, ConnectSocket);
        //start mining in this thread
        start_mining();

        t1.join();
        //if we join it is because 
        // lost socket connection
        //cleanup and reconnect via main loop
        miner.need_stop = true;
        closesocket(ConnectSocket);
        WSACleanup();
        //main_loop();
    }

    winrt::fire_and_forget MainPage::Button_Click(IInspectable const&, RoutedEventArgs const&) {
        //std::thread t1(start_mining);
        co_await winrt::resume_background();
        //miner.set_test_vars();
        //miner.mine_forever();
        main_loop();

        //return NULL;
    }

    void MainPage::ClickHandler(IInspectable const&, RoutedEventArgs const&)
    {




        return;
        auto i = devicesComboBox().SelectedIndex();
        if (i < 0) {
            MessageDialog dialog(L"A device must be selected.");
            dialog.ShowAsync();
            return;
        }
        auto x = constants.GetCacheSize(0);
        myButton().Content(winrt::box_value(std::to_wstring(x)));
        pivot().SelectedItem(winrt::box_value(statusPivotItem()));
        auto miner = DXMiner(i);
    }
}


