#include <urlmon.h>

class NLMCallBack : public IBindStatusCallback
{
	virtual HRESULT STDMETHODCALLTYPE QueryInterface( 
		/* [in] */ REFIID riid,
		/* [iid_is][out] */ void __RPC_FAR *__RPC_FAR *ppvObject)
	{ TRACE("NLMCallBack::QueryInterface"); return E_NOTIMPL; }

	virtual ULONG STDMETHODCALLTYPE AddRef( void)
	{ TRACE("NLMCallBack::AddRef"); return 2; }

	virtual ULONG STDMETHODCALLTYPE Release( void)
	{ TRACE("NLMCallBack::Release"); return 1; }

	virtual HRESULT STDMETHODCALLTYPE OnStartBinding( 
		/* [in] */ DWORD dwReserved,
		/* [in] */ IBinding *pib)
	{ TRACE("NLMCallBack::OnStartBinding"); return E_NOTIMPL; }

	virtual HRESULT STDMETHODCALLTYPE GetPriority( 
		/* [out] */ LONG *pnPriority)
	{ TRACE("NLMCallBack::GetPriority"); return E_NOTIMPL; }

	virtual HRESULT STDMETHODCALLTYPE OnLowResource( 
		/* [in] */ DWORD reserved) 
	{ TRACE("NLMCallBack::OnLowResource"); return E_NOTIMPL; }

	virtual HRESULT STDMETHODCALLTYPE OnProgress( 
		/* [in] */ ULONG ulProgress,
		/* [in] */ ULONG ulProgressMax,
		/* [in] */ ULONG ulStatusCode,
		/* [in] */ LPCWSTR szStatusText);

	virtual HRESULT STDMETHODCALLTYPE OnStopBinding( 
		/* [in] */ HRESULT hresult,
		/* [unique][in] */ LPCWSTR szError)
	{ TRACE("NLMCallBack::OnStopBinding"); return E_NOTIMPL; }

	virtual /* [local] */ HRESULT STDMETHODCALLTYPE GetBindInfo( 
		/* [out] */ DWORD *grfBINDF,
		/* [unique][out][in] */ BINDINFO *pbindinfo)
	{ TRACE("NLMCallBack::GetBindInfo"); return E_NOTIMPL; }

	virtual /* [local] */ HRESULT STDMETHODCALLTYPE OnDataAvailable( 
		/* [in] */ DWORD grfBSCF,
		/* [in] */ DWORD dwSize,
		/* [in] */ FORMATETC *pformatetc,
		/* [in] */ STGMEDIUM *pstgmed)
	{ TRACE("NLMCallBack::OnDataAvailable"); return E_NOTIMPL; }

	virtual HRESULT STDMETHODCALLTYPE OnObjectAvailable( 
		/* [in] */ REFIID riid,
		/* [iid_is][in] */ IUnknown *punk)
	{ TRACE("NLMCallBack::OnObjectAvailable"); return E_NOTIMPL; }
};

extern NLMCallBack NLMStatusCallback;
