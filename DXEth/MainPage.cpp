#include "pch.h"
#include "MainPage.h"
#include "MainPage.g.cpp"

#include <codecvt>
#include "DXMiner.h"
#include "Constants.h"

using namespace winrt;
using namespace Windows::UI::Core;
using namespace Windows::UI::Popups;
using namespace Windows::UI::Xaml;
using namespace Windows::Foundation;

namespace winrt::DXEth::implementation
{
    MainPage::MainPage()
    {
        auto deviceList = DXMiner::listDevices();
        std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>, wchar_t> wcharConv;
        InitializeComponent();
        for (auto& device : deviceList) {
            devicesComboBox().Items().Append(PropertyValue::CreateString(wcharConv.from_bytes(device)));
        }

        auto x = constants.GetCacheSize(0);
        auto miner = DXMiner(0);
    }

    int32_t MainPage::MyProperty()
    {
        throw hresult_not_implemented();
    }

    void MainPage::MyProperty(int32_t /* value */)
    {
        throw hresult_not_implemented();
    }

    void MainPage::ClickHandler(IInspectable const&, RoutedEventArgs const&)
    {
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
