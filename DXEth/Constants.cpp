#include "pch.h"

#include "Constants.h"
#include <fstream>
#include <iostream>
#include <string>
#include<libdevcore/FixedHash.h>
using namespace winrt;

namespace winrt::DXEth {
	Constants constants;
	Constants::Constants() {
		std::wstring path = Windows::ApplicationModel::Package::Current().InstalledLocation().Path().c_str();
		auto cacheSizesPath = path + L"/Assets/CacheSizes.txt";
		auto datasetSizesPath = path + L"/Assets/DatasetSizes.txt";
		auto seedsPath = path + L"/Assets/Seeds.txt";
		std::ifstream cacheSizesStream(cacheSizesPath.c_str());
		std::ifstream datasetSizesStream(datasetSizesPath.c_str());
		std::ifstream seedsStream(seedsPath.c_str());
		std::string line;
		while (std::getline(cacheSizesStream, line)) {
			m_cacheSizes.push_back(std::stoull(line));
		}
		while (std::getline(datasetSizesStream, line)) {
			m_datasetSizes.push_back(std::stoull(line));
		}
		while (std::getline(seedsStream, line)) {
			if (line.size() != 64) {
				throw std::runtime_error("bad seed size");
			}
			int x;
			std::array<uint8_t, 32> arr;
			for (size_t i = 0; i < arr.size(); i++) {
				std::sscanf(&line.c_str()[i * 2], "%02x", &x);
				arr[i] = (uint8_t)x;
			}

			auto seed_h256 = dev::h256(line);

			m_seeds.push_back(seed_h256);
		}
		cacheSizesStream.close();
	}

	size_t Constants::GetEpochs() {
		return std::min(std::min(m_cacheSizes.size(), m_datasetSizes.size()), m_seeds.size());
	}

	size_t Constants::GetCacheSize(int epoch) {
		if (epoch < 0 || epoch >= m_cacheSizes.size())
			throw std::range_error("Epoch out of range");
		return m_cacheSizes[epoch];
	}

	size_t Constants::GetDatasetSize(int epoch) {
		if (epoch < 0 || epoch >= m_cacheSizes.size())
			throw std::range_error("Epoch out of range");
		return m_datasetSizes[epoch];
	}

	dev::h256 Constants::GetSeed(int epoch) {
		if (epoch < 0 || epoch >= m_cacheSizes.size())
			throw std::range_error("Epoch out of range");
		return m_seeds[epoch];
	}
}
