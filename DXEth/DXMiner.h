#pragma once
#define _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS 1

#include <iostream>
#include <string>

#include <d3d12.h>
#include <dxgi1_6.h>

namespace winrt::DXEth {
	class DXMiner {
	public:
		DXMiner(size_t deviceIndex);
		void mine(
			int epoch,
			std::array<uint8_t, 32> target,
			std::array<uint8_t, 32> header,
			uint64_t nonce,
			uint64_t count
		);
		size_t getBatchSize();
		void setBatchSize(size_t size);
		static std::vector<std::string> listDevices();
	private:
		void prepareEpoch(int epoch);
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

		int m_epoch = -1;
		UINT m_batchSize = 64 * 1024;
	};
}
