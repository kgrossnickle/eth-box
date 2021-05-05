#include "pch.h"
#include "DXMiner.h"
#include <iostream>

#include <chrono>
#include <codecvt>

#include <d3d12.h>
#include <dxgi1_6.h>
#include <d3dcompiler.h>

#include "d3dx12.h"

#include <exception>

#include "Constants.h"
#include "keccak.h"


#define PUT_GENERIC_COM_PTR(x) __uuidof(x), x.put_void()
#define COMPUTE_SHADER_NUM_THREADS 16
#define MAX_FOUND 16

using namespace winrt;

namespace winrt::DXEth {
	struct GenerateDatasetParam {
		uint32_t numDatasetElements;
		uint32_t numCacheElements;
		uint32_t datasetGenerationOffset;
	};

	struct MineParam {
		uint32_t target[8];
		uint32_t header[8];
		uint32_t startNonce[2];
		uint32_t numDatasetElements;
		uint32_t init;
	};

	struct MineResult {
		uint32_t count;    // 4 bytes
		uint32_t pad;
		struct {
			uint32_t nonce[2]; // 8 bytes
		} nonces[MAX_FOUND];
	};

	DXMiner::DXMiner(size_t index) {
		assert(sizeof(MineParam) == 80);
#if defined(_DEBUG)
		// check_hresult(D3D12GetDebugInterface(PUT_GENERIC_COM_PTR(m_debugController)));
		// m_debugController->EnableDebugLayer();
#endif
		com_ptr<IDXGIFactory4> dxgiFactory;
		com_ptr<IDXGIAdapter1> dxgiAdapter1;
		std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
		std::vector<std::string> l;
		UINT createFactoryFlags = 0;
#if defined(_DEBUG)
		// createFactoryFlags = DXGI_CREATE_FACTORY_DEBUG;
#endif
		check_hresult(CreateDXGIFactory2(0, PUT_GENERIC_COM_PTR(dxgiFactory)));
		for (UINT i = 0; dxgiAdapter1 = nullptr, SUCCEEDED(dxgiFactory->EnumAdapters1(i, dxgiAdapter1.put())); i++) {
			if (i == index) {
				DXGI_ADAPTER_DESC1 dxgiAdapterDesc1;
				dxgiAdapter1->GetDesc1(&dxgiAdapterDesc1);
				OutputDebugString(L"Creating Device: ");
				OutputDebugString(dxgiAdapterDesc1.Description);
				OutputDebugString(L"\n");
				check_hresult(D3D12CreateDevice(dxgiAdapter1.get(), D3D_FEATURE_LEVEL_11_0, PUT_GENERIC_COM_PTR(m_d3d12Device)));
				break;
			}
		}
#if defined(_DEBUG)
		{
			auto infoQueue = m_d3d12Device.try_as<ID3D12InfoQueue>();
			if (infoQueue != nullptr) {
				infoQueue->SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY_CORRUPTION, TRUE);
				infoQueue->SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY_ERROR, TRUE);
				infoQueue->SetBreakOnSeverity(D3D12_MESSAGE_SEVERITY_WARNING, TRUE);

				D3D12_MESSAGE_SEVERITY Severities[] =
				{
					D3D12_MESSAGE_SEVERITY_INFO
				};

				// Suppress individual messages by their ID
				D3D12_MESSAGE_ID DenyIds[] = {
					D3D12_MESSAGE_ID_CLEARRENDERTARGETVIEW_MISMATCHINGCLEARVALUE,   // I'm really not sure how to avoid this message.
					D3D12_MESSAGE_ID_MAP_INVALID_NULLRANGE,                         // This warning occurs when using capture frame while graphics debugging.
					D3D12_MESSAGE_ID_UNMAP_INVALID_NULLRANGE,                       // This warning occurs when using capture frame while graphics debugging.
				};

				D3D12_INFO_QUEUE_FILTER NewFilter = {};
				//NewFilter.DenyList.NumCategories = _countof(Categories);
				//NewFilter.DenyList.pCategoryList = Categories;
				NewFilter.DenyList.NumSeverities = 0;//_countof(Severities);
				NewFilter.DenyList.pSeverityList = nullptr;//Severities;
				NewFilter.DenyList.NumIDs = _countof(DenyIds);
				NewFilter.DenyList.pIDList = DenyIds;

				check_hresult(infoQueue->PushStorageFilter(&NewFilter));
			}
		}
#endif

		{ // create command queue for compute
			D3D12_COMMAND_QUEUE_DESC desc = {};
			desc.Type = D3D12_COMMAND_LIST_TYPE_COMPUTE;
			desc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
			desc.Flags = D3D12_COMMAND_QUEUE_FLAG_DISABLE_GPU_TIMEOUT;
			desc.NodeMask = 0;
			check_hresult(m_d3d12Device->CreateCommandQueue(&desc, PUT_GENERIC_COM_PTR(m_d3d12ComputeCommandQueue)));
			m_d3d12ComputeCommandQueue->SetName(L"ComputeCommandQueue");
		}

		{ // create command queue for copy
			D3D12_COMMAND_QUEUE_DESC desc = {};
			desc.Type = D3D12_COMMAND_LIST_TYPE_COPY;
			desc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
			desc.Flags = D3D12_COMMAND_QUEUE_FLAG_DISABLE_GPU_TIMEOUT;
			desc.NodeMask = 0;
			check_hresult(m_d3d12Device->CreateCommandQueue(&desc, PUT_GENERIC_COM_PTR(m_d3d12CopyCommandQueue)));
			m_d3d12CopyCommandQueue->SetName(L"CopyCommandQueue");
		}

		std::wstring AppPath = Windows::ApplicationModel::Package::Current().InstalledLocation().Path().c_str();

		OutputDebugString(L"rs generateDataset\n");
		{ // create root signature for generateDataset

			CD3DX12_ROOT_PARAMETER1 rootParameters[6] = {};
			for (UINT i = 0; i < 5; i++)
				rootParameters[i].InitAsUnorderedAccessView(i);
			rootParameters[5].InitAsConstants(sizeof(GenerateDatasetParam) / 4, 0);
			CD3DX12_VERSIONED_ROOT_SIGNATURE_DESC rootSignatureDesc;
			rootSignatureDesc.Init_1_1(6, rootParameters);
			com_ptr<ID3DBlob> signature;
			com_ptr<ID3DBlob> error;
			check_hresult(D3DX12SerializeVersionedRootSignature(&rootSignatureDesc, D3D_ROOT_SIGNATURE_VERSION_1_1, signature.put(), error.put()));
			check_hresult(m_d3d12Device->CreateRootSignature(0, signature->GetBufferPointer(), signature->GetBufferSize(), PUT_GENERIC_COM_PTR(m_generateDatasetRootSignature)));
			m_generateDatasetRootSignature->SetName(L"GenerateDatasetRootSignature");
			// load shader
			auto path = AppPath + L"\\Assets\\ETHashGenerateDataset.cso";
			check_hresult(D3DReadFileToBlob(path.c_str(), m_generateDatasetShader.put()));

			D3D12_COMPUTE_PIPELINE_STATE_DESC computePsoDesc = {};
			computePsoDesc.pRootSignature = m_generateDatasetRootSignature.get();
			computePsoDesc.CS = CD3DX12_SHADER_BYTECODE(m_generateDatasetShader.get());
			check_hresult(m_d3d12Device->CreateComputePipelineState(&computePsoDesc, PUT_GENERIC_COM_PTR(m_generateDatasetPipelineState)));
			m_generateDatasetPipelineState->SetName(L"GenerateDatasetPipelineState");
		}

		OutputDebugString(L"rs mine\n");
		{ // create root signature for mine
			CD3DX12_ROOT_PARAMETER1 rootParameters[6] = {};
			for (UINT i = 0; i < 5; i++)
				rootParameters[i].InitAsUnorderedAccessView(i);
			rootParameters[5].InitAsConstants(sizeof(MineParam) / 4, 0);
			CD3DX12_VERSIONED_ROOT_SIGNATURE_DESC rootSignatureDesc;
			rootSignatureDesc.Init_1_1(6, rootParameters);
			com_ptr<ID3DBlob> signature;
			com_ptr<ID3DBlob> error;
			OutputDebugString(L"rs D3DX12SerializeVersionedRootSignature\n");
			check_hresult(D3DX12SerializeVersionedRootSignature(&rootSignatureDesc, D3D_ROOT_SIGNATURE_VERSION_1_1, signature.put(), error.put()));
			OutputDebugString(L"rs CreateRootSignature\n");
			check_hresult(m_d3d12Device->CreateRootSignature(0, signature->GetBufferPointer(), signature->GetBufferSize(), PUT_GENERIC_COM_PTR(m_mineRootSignature)));
			m_mineRootSignature->SetName(L"MineRootSignature");
			// load shader
			auto path = AppPath + L"\\Assets\\ETHashMine.cso";
			check_hresult(D3DReadFileToBlob(path.c_str(), m_mineShader.put()));
			// OutputDebugString(std::to_wstring(m_mineShader->GetBufferSize()).c_str());
			D3D12_COMPUTE_PIPELINE_STATE_DESC computePsoDesc = {};
			computePsoDesc.pRootSignature = m_mineRootSignature.get();
			computePsoDesc.CS = CD3DX12_SHADER_BYTECODE(m_mineShader.get());
			OutputDebugString(L"rs CreateComputePipelineState\n");
			check_hresult(m_d3d12Device->CreateComputePipelineState(&computePsoDesc, PUT_GENERIC_COM_PTR(m_minePipelineState)));
			m_minePipelineState->SetName(L"MinePipelineState");
		}

		OutputDebugString(L"allocators and lists\n");
		{ // Create command allocator and list
			check_hresult(m_d3d12Device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_COMPUTE, PUT_GENERIC_COM_PTR(m_d3d12ComputeCommandAllocator)));
			check_hresult(m_d3d12Device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_COMPUTE, m_d3d12ComputeCommandAllocator.get(), nullptr, PUT_GENERIC_COM_PTR(m_d3d12ComputeCommandList)));
			check_hresult(m_d3d12ComputeCommandList->Close());

			check_hresult(m_d3d12Device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_COPY, PUT_GENERIC_COM_PTR(m_d3d12CopyCommandAllocator)));
			check_hresult(m_d3d12Device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_COPY, m_d3d12CopyCommandAllocator.get(), nullptr, PUT_GENERIC_COM_PTR(m_d3d12CopyCommandList)));
			check_hresult(m_d3d12CopyCommandList->Close());
		}

		{ // create fence
			check_hresult(m_d3d12Device->CreateFence(0, D3D12_FENCE_FLAG_SHARED, PUT_GENERIC_COM_PTR(m_d3d12Fence)));
			m_fenceValue = 0;
		}

		OutputDebugString(L"Prepare for Epoch\n");
		// prepareEpoch(0);
		mine(0, std::array<uint8_t, 32>(), std::array<uint8_t, 32>(), 0, getBatchSize());
	}

	size_t DXMiner::getBatchSize() {
		return m_batchSize;
	}

	void DXMiner::setBatchSize(size_t batchSize) {
		m_batchSize = (UINT)batchSize;
	}

	void DXMiner::waitForQueue(com_ptr<ID3D12CommandQueue>& q) {
		m_fenceValue++;
		check_hresult(q->Signal(m_d3d12Fence.get(), m_fenceValue));
		auto fenceEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
		if (fenceEvent == 0) {
			throw std::runtime_error("cannot create fenceEvent");
		}
		if (m_d3d12Fence->GetCompletedValue() < m_fenceValue) {
			check_hresult(m_d3d12Fence->SetEventOnCompletion(m_fenceValue, fenceEvent));
			WaitForSingleObject(fenceEvent, INFINITE);
		}
	}

	std::vector<uint64_t> DXMiner::mine(
		int epoch,
		std::array<uint8_t, 32> target,
		std::array<uint8_t, 32> header,
		uint64_t startNonce,
		uint64_t count
	) {
		prepareEpoch(epoch);
		size_t hashBytes = 64;
		size_t datasetSize = constants.GetDatasetSize(epoch);
		if (count % m_batchSize) {
			throw std::runtime_error("count must be a multiple of batch size");
		}
		// m_batchSize = 64;

		OutputDebugString(L"Total nonces run \n");
		OutputDebugString(std::to_wstring(count).c_str());
		OutputDebugString(L"\nbatch size \n");
		OutputDebugString(std::to_wstring(m_batchSize).c_str());
		auto startTime = std::chrono::high_resolution_clock::now();
		{ // run mining
			uint32_t numDatasetElements = datasetSize / hashBytes;
			MineParam param = {};
			param.numDatasetElements = numDatasetElements;
			param.init = 1;
			std::array<uint8_t, 8> hard_coded_target;
			hard_coded_target[0] = 0;
			hard_coded_target[1] = 9;
			/*
			hard_coded_target[2] = 0;
			hard_coded_target[3] = 0;
			hard_coded_target[4] = 0;
			hard_coded_target[5] = 0;
			hard_coded_target[6] = 0;
			hard_coded_target[7] = 0;*/
			//param.target = hard_coded_target;
			memcpy(param.target, hard_coded_target.data(), hard_coded_target.size());
			//memcpy(param.target, target.data(), target.size());
			memcpy(param.header, header.data(), header.size());


			for (uint64_t i = 0; i < count; i += m_batchSize) {
				param.startNonce[0] = (startNonce + i) & ((1ULL << 32) - 1);
				param.startNonce[1] = (startNonce + i) >> 32;
				check_hresult(m_d3d12ComputeCommandAllocator->Reset());
				check_hresult(m_d3d12ComputeCommandList->Reset(m_d3d12ComputeCommandAllocator.get(), m_minePipelineState.get()));
				m_d3d12ComputeCommandList->SetPipelineState(m_minePipelineState.get());
				m_d3d12ComputeCommandList->SetComputeRootSignature(m_mineRootSignature.get());
				for (size_t i = 0; i < 4; i++) {
					m_d3d12ComputeCommandList->SetComputeRootUnorderedAccessView(i, m_datasetBuffers[i]->GetGPUVirtualAddress());
				}
				m_d3d12ComputeCommandList->SetComputeRootUnorderedAccessView(4, m_resultBuffer->GetGPUVirtualAddress());
				m_d3d12ComputeCommandList->SetComputeRoot32BitConstants(5, sizeof(param) / 4, reinterpret_cast<void*>(&param), 0);

				//orig = m_batchSize / COMPUTE_SHADER_NUM_THREADS
				int num_threads = m_batchSize / COMPUTE_SHADER_NUM_THREADS;// 32;
				//OutputDebugString(L"Num threads is \n");
				//OutputDebugString(std::to_wstring(num_threads).c_str());
				m_d3d12ComputeCommandList->Dispatch(m_batchSize / COMPUTE_SHADER_NUM_THREADS, 1, 1);
				param.init = 0;

				// Schedule to copy the data to the default buffer to the readback buffer.
				m_d3d12ComputeCommandList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(m_resultBuffer.get(),
					D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_SOURCE));

				m_d3d12ComputeCommandList->CopyResource(m_resultReadbackBuffer.get(), m_resultBuffer.get());

				m_d3d12ComputeCommandList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(m_resultBuffer.get(),
					D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_COMMON));

				check_hresult(m_d3d12ComputeCommandList->Close());
				ID3D12CommandList* ppCommandLists[] = { m_d3d12ComputeCommandList.get() };

				m_d3d12ComputeCommandQueue->ExecuteCommandLists(1, ppCommandLists);
				waitForQueue(m_d3d12ComputeCommandQueue);

			}
		}
		

		MineResult* md = nullptr;
		check_hresult(m_resultReadbackBuffer->Map(0, nullptr, reinterpret_cast<void**>(&md)));

		OutputDebugString(L"count of nonces from res buffer \n");
		OutputDebugString(std::to_wstring(md[0].count).c_str());
		OutputDebugString(L"\nfirst nonce \n");
		OutputDebugString(std::to_wstring(md[0].nonces[0].nonce[0]).c_str());
		OutputDebugString(L" ");
		OutputDebugString(std::to_wstring(md[0].nonces[0].nonce[1]).c_str());
		OutputDebugString(L"\n");
		m_resultReadbackBuffer->Unmap(0, nullptr);

		auto endTime = std::chrono::high_resolution_clock::now();
		auto elapsed = endTime - startTime;
		auto ms = elapsed / std::chrono::microseconds(1);
		OutputDebugString(L"microsconds taken: ");
		OutputDebugString(std::to_wstring(ms).c_str());
		OutputDebugString(L"\n");
		auto mhs = (float)count / (float)ms;
		OutputDebugString(L"MHS: ");
		OutputDebugString(std::to_wstring(mhs).c_str());
		OutputDebugString(L"\n");
		return std::vector<uint64_t>();
	}

	void DXMiner::prepareEpoch(int epoch) {
		if (epoch < 0) {
			throw std::out_of_range("bad epoch");
		}
		if (epoch == m_epoch) {
			return;
		}

		// generate cache, and upload to GPU

		size_t hashBytes = 64;
		size_t cacheSize = constants.GetCacheSize(epoch);
		size_t datasetSize = constants.GetDatasetSize(epoch);
		{
			// create upload buffer
			uint8_t* cacheData;
			m_cacheUploadBuffer = nullptr;
			D3D12_RESOURCE_ALLOCATION_INFO resourceAllocationInfo;
			resourceAllocationInfo.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
			resourceAllocationInfo.SizeInBytes = cacheSize;
			check_hresult(m_d3d12Device->CreateCommittedResource(
				&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_UPLOAD),
				D3D12_HEAP_FLAG_NONE,
				&CD3DX12_RESOURCE_DESC::Buffer(resourceAllocationInfo),
				D3D12_RESOURCE_STATE_GENERIC_READ,
				nullptr,
				PUT_GENERIC_COM_PTR(m_cacheUploadBuffer)
			));
			CD3DX12_RANGE range(0, cacheSize);

			m_cacheUploadBuffer->Map(0, &range, reinterpret_cast<void**>(&cacheData));
			auto seed = constants.GetSeed(epoch);
			keccak(seed.data(), seed.size(), cacheData, hashBytes);
			for (size_t offset = hashBytes; offset < cacheSize; offset += hashBytes) {
				keccak(cacheData + offset - hashBytes, hashBytes, cacheData + offset, hashBytes);
			}
			m_cacheUploadBuffer->Unmap(0, &range);
		}

		{ // create UAV for cache
			D3D12_RESOURCE_ALLOCATION_INFO resourceAllocationInfo;
			resourceAllocationInfo.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
			resourceAllocationInfo.SizeInBytes = cacheSize;

			m_cacheBuffer = nullptr;

			check_hresult(m_d3d12Device->CreateCommittedResource(
				&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
				D3D12_HEAP_FLAG_NONE,
				&CD3DX12_RESOURCE_DESC::Buffer(resourceAllocationInfo, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS),
				D3D12_RESOURCE_STATE_COPY_DEST,
				nullptr,
				PUT_GENERIC_COM_PTR(m_cacheBuffer)
			));

			// m_d3d12CopyCommandList->SetComputeRootUnorderedAccessView(4, m_cacheBuffer->GetGPUVirtualAddress());
		}

		{ // create UAVs for datasets
			D3D12_RESOURCE_ALLOCATION_INFO resourceAllocationInfo;
			resourceAllocationInfo.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
			resourceAllocationInfo.SizeInBytes = ((datasetSize / hashBytes / 4) + 1) * hashBytes;
			for (size_t i = 0; i < 4; i++) {
				m_datasetBuffers[i] = nullptr;
				check_hresult(m_d3d12Device->CreateCommittedResource(
					&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
					D3D12_HEAP_FLAG_NONE,
					&CD3DX12_RESOURCE_DESC::Buffer(resourceAllocationInfo, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS),
					D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
					nullptr,
					PUT_GENERIC_COM_PTR(m_datasetBuffers[i])
				));

				// m_d3d12CopyCommandList->SetComputeRootUnorderedAccessView(i, m_datasetBuffers[i]->GetGPUVirtualAddress());
			}
		}

		{ // copy to GPU
			check_hresult(m_d3d12CopyCommandAllocator->Reset());
			check_hresult(m_d3d12CopyCommandList->Reset(m_d3d12CopyCommandAllocator.get(), nullptr));
			m_d3d12CopyCommandList->CopyResource(m_cacheBuffer.get(), m_cacheUploadBuffer.get());
			// m_d3d12CopyCommandList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(m_cacheBuffer.get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_UNORDERED_ACCESS));
			check_hresult(m_d3d12CopyCommandList->Close());
			ID3D12CommandList* ppCommandLists[] = { m_d3d12CopyCommandList.get() };
			m_d3d12CopyCommandQueue->ExecuteCommandLists(1, ppCommandLists);
			waitForQueue(m_d3d12CopyCommandQueue);
		}

		{ // run dataset generation
			uint32_t numDatasetElements = datasetSize / hashBytes;
			uint32_t batchSize = std::min(m_batchSize, numDatasetElements);
			GenerateDatasetParam param = {};
			param.datasetGenerationOffset = 0;
			param.numCacheElements = cacheSize / hashBytes;
			param.numDatasetElements = datasetSize / hashBytes;
			for (uint32_t curElement = 0; curElement < numDatasetElements; curElement += batchSize) {
				param.datasetGenerationOffset = curElement;

				check_hresult(m_d3d12ComputeCommandAllocator->Reset());
				check_hresult(m_d3d12ComputeCommandList->Reset(m_d3d12ComputeCommandAllocator.get(), m_generateDatasetPipelineState.get()));
				m_d3d12ComputeCommandList->SetPipelineState(m_generateDatasetPipelineState.get());
				m_d3d12ComputeCommandList->SetComputeRootSignature(m_generateDatasetRootSignature.get());
				for (size_t i = 0; i < 4; i++) {
					m_d3d12ComputeCommandList->SetComputeRootUnorderedAccessView(i, m_datasetBuffers[i]->GetGPUVirtualAddress());
				}
				m_d3d12ComputeCommandList->SetComputeRootUnorderedAccessView(4, m_cacheBuffer->GetGPUVirtualAddress());
				m_d3d12ComputeCommandList->SetComputeRoot32BitConstants(5, sizeof(param) / 4, reinterpret_cast<void*>(&param), 0);
				m_d3d12ComputeCommandList->Dispatch(batchSize / COMPUTE_SHADER_NUM_THREADS, 1, 1);
				check_hresult(m_d3d12ComputeCommandList->Close());
				ID3D12CommandList* ppCommandLists[] = { m_d3d12ComputeCommandList.get() };

				m_d3d12ComputeCommandQueue->ExecuteCommandLists(1, ppCommandLists);
				waitForQueue(m_d3d12ComputeCommandQueue);
				//OutputDebugString(L"CurElement: ");
				//OutputDebugString(std::to_wstring(curElement).c_str());
				//OutputDebugString(L"\n");
			}
		}

		{
			// free cache buffer
			// m_cacheUploadBuffer = nullptr;
			// m_cacheBuffer = nullptr;
		}

		{
			// create result buffer
			D3D12_RESOURCE_ALLOCATION_INFO resourceAllocationInfo;
			resourceAllocationInfo.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
			resourceAllocationInfo.SizeInBytes = sizeof(MineResult);
			m_resultReadbackBuffer = nullptr;
			check_hresult(m_d3d12Device->CreateCommittedResource(
				&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
				D3D12_HEAP_FLAG_ALLOW_SHADER_ATOMICS,
				&CD3DX12_RESOURCE_DESC::Buffer(resourceAllocationInfo, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS),
				D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
				nullptr,
				PUT_GENERIC_COM_PTR(m_resultBuffer)
			));
		}

		{
			// create result read back buffer
			D3D12_RESOURCE_ALLOCATION_INFO resourceAllocationInfo;
			resourceAllocationInfo.Alignment = D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT;
			resourceAllocationInfo.SizeInBytes = sizeof(MineResult);
			m_resultReadbackBuffer = nullptr;
			check_hresult(m_d3d12Device->CreateCommittedResource(
				&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_READBACK),
				D3D12_HEAP_FLAG_NONE,
				&CD3DX12_RESOURCE_DESC::Buffer(resourceAllocationInfo),
				D3D12_RESOURCE_STATE_COPY_DEST,
				nullptr,
				PUT_GENERIC_COM_PTR(m_resultReadbackBuffer)
			));
		}

		m_epoch = epoch;
	}

	std::vector<std::string> DXMiner::listDevices() {
		com_ptr<IDXGIFactory4> dxgiFactory;
		com_ptr<IDXGIAdapter1> dxgiAdapter1;
		std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
		std::vector<std::string> l;
		check_hresult(CreateDXGIFactory2(0, __uuidof(dxgiFactory), dxgiFactory.put_void()));
		for (UINT i = 0; dxgiAdapter1 = nullptr, SUCCEEDED(dxgiFactory->EnumAdapters1(i, dxgiAdapter1.put())); i++) {
			DXGI_ADAPTER_DESC1 dxgiAdapterDesc1;
			dxgiAdapter1->GetDesc1(&dxgiAdapterDesc1);
			if (SUCCEEDED(D3D12CreateDevice(dxgiAdapter1.get(), D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), nullptr)))
				l.push_back(converter.to_bytes(dxgiAdapterDesc1.Description));
		}
		return l;
	}
}
