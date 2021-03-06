#pragma once
#include <array>
#include <vector>
#include<libdevcore/FixedHash.h>

namespace winrt::DXEth {
	class Constants
	{
	public:
		Constants();
		size_t GetEpochs();
		size_t GetCacheSize(int epoch);
		size_t GetDatasetSize(int epoch);
		//std::array<uint8_t, 32> GetSeed(int epoch);
		dev::h256 GetSeed(int epoch);
		int find_epoch_from_seed(std::string);
	private:
		std::vector<size_t> m_cacheSizes;
		std::vector<size_t> m_datasetSizes;
		//std::vector<std::array<uint8_t, 32>> m_seeds;
		std::vector<dev::h256> m_seeds;
		
	};
	extern Constants constants;
}
