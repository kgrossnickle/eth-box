#pragma once
#define _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS 1

#include <iostream>
#include <string>

#include <d3d12.h>
#include <dxgi1_6.h>
#include "Constants.h"
#include "keccak.h"
#include"libdevcore/FixedHash.cpp"
#include <codecvt>
#include <ethash/ethash.hpp>

namespace winrt::DXEth {
	class DXMiner {
	public:
		DXMiner();
		DXMiner(size_t deviceIndex);
		void mine(
			int epoch,
			std::array<uint8_t, 32> target,
			std::array<uint8_t, 32> header,
			uint64_t nonce,
			uint64_t count
		);
		void mine_once();
		void mine_forever();
		void set_test_vars();
		size_t getBatchSize();
		void setBatchSize(size_t size);
		static std::vector<std::string> listDevices();
		void set_cur_nonce_from_extra_nonce();
		void set_h256_header();
		void set_debug_boundary_from_hash_str(std::string);
		bool need_stop = true;
		bool has_block_info = false;
		bool has_boundary = false;
		bool has_extra_nonce = false;
		h256 m_header;
		h256 m_boundary;
		int m_epoch;
		uint64_t m_cur_nonce;
		std::string m_header_hash;
		std::string m_extra_nonce_str;
		std::string m_stratum_id;
		std:: string m_job_id;
		std::string m_seed = "";
		uint64_t prev_res_nonce = 0;
		int runs = 0;
		int m_block_num;
		std::vector<std::string> solutions; //jobid,nonce . needs to be split in maincpp. Extra nonce is already removed tho
		double m_difficulty_as_dbl;
		void prepareEpoch();
		void set_boundary_from_diff();

	private:
		void waitForQueue(com_ptr<ID3D12CommandQueue> &q);
		com_ptr<ID3D12Debug> m_debugController;
		com_ptr<ID3D12Device1> m_d3d12Device;
		
		com_ptr<ID3D12CommandQueue> m_d3d12ComputeCommandQueue;
		com_ptr<ID3D12CommandQueue> m_d3d12CopyCommandQueue;

		com_ptr<ID3D12CommandAllocator> m_d3d12ComputeCommandAllocator;
		com_ptr<ID3D12CommandAllocator> m_d3d12CopyCommandAllocator;

		com_ptr<ID3D12GraphicsCommandList> m_d3d12ComputeCommandList;
		com_ptr<ID3D12GraphicsCommandList> m_d3d12CopyCommandList;

		com_ptr<ID3D12RootSignature> m_generateDatasetRootSignature;
		com_ptr<ID3D12RootSignature> m_mineRootSignature;

		com_ptr<ID3D12PipelineState> m_generateDatasetPipelineState;
		com_ptr<ID3D12PipelineState> m_minePipelineState;
		
		com_ptr<ID3DBlob> m_generateDatasetShader;
		com_ptr<ID3DBlob> m_mineShader;

		com_ptr<ID3D12Resource> m_cacheUploadBuffer;
		com_ptr<ID3D12Resource> m_cacheBuffer;
		com_ptr<ID3D12Resource> m_resultBuffer;
		com_ptr<ID3D12Resource> m_resultReadbackBuffer;
		std::array<com_ptr<ID3D12Resource>, 4> m_datasetBuffers;
		
		std::array<com_ptr<ID3D12Resource>, 4> m_ethashDatasetShardResources;
		com_ptr<ID3D12Resource> m_ethashCacheResource;
		
		com_ptr<ID3D12Fence> m_d3d12Fence;
		UINT64 m_fenceValue;

		UINT m_batchSize = 64 * 1024;
	};
}
