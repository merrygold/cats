foodBridge.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

enum DestinationTransferStatus {
  None, // 0
  Reconciled, // 1
  Executed, // 2
  Completed // 3 - executed + reconciled
}

struct TransferInfo {
  uint32 originDomain;
  uint32 destinationDomain;
  uint32 canonicalDomain;
  address to;
  address delegate;
  bool receiveLocal;
  bytes callData;
  uint256 slippage;
  address originSender;
  uint256 bridgedAmt;
  uint256 normalizedIn;
  uint256 nonce;
  bytes32 canonicalId;
}


struct ExecuteArgs {
  TransferInfo params;
  address[] routers;
  bytes[] routerSignatures;
  address sequencer;
  bytes sequencerSignature;
}
struct TokenId {
  uint32 domain;
  bytes32 id;
}

interface IConnext {

  // ============ BRIDGE ==============

  function xcall(
    uint32 _destination,
    address _to,
    address _asset,
    address _delegate,
    uint256 _amount,
    uint256 _slippage,
    bytes calldata _callData
  ) external payable returns (bytes32);

  function xcall(
    uint32 _destination,
    address _to,
    address _asset,
    address _delegate,
    uint256 _amount,
    uint256 _slippage,
    bytes calldata _callData,
    uint256 _relayerFee
  ) external returns (bytes32);

  function xcallIntoLocal(
    uint32 _destination,
    address _to,
    address _asset,
    address _delegate,
    uint256 _amount,
    uint256 _slippage,
    bytes calldata _callData
  ) external payable returns (bytes32);

  function execute(ExecuteArgs calldata _args) external returns (bytes32 transferId);

  function forceUpdateSlippage(TransferInfo calldata _params, uint256 _slippage) external;

  function forceReceiveLocal(TransferInfo calldata _params) external;

  function bumpTransfer(bytes32 _transferId) external payable;

  function routedTransfers(bytes32 _transferId) external view returns (address[] memory);

  function transferStatus(bytes32 _transferId) external view returns (DestinationTransferStatus);

  function remote(uint32 _domain) external view returns (address);

  function domain() external view returns (uint256);

  function nonce() external view returns (uint256);

  function approvedSequencers(address _sequencer) external view returns (bool);

  function xAppConnectionManager() external view returns (address);

  // ============ ROUTERS ==============

  function LIQUIDITY_FEE_NUMERATOR() external view returns (uint256);

  function LIQUIDITY_FEE_DENOMINATOR() external view returns (uint256);

  function getRouterApproval(address _router) external view returns (bool);

  function getRouterRecipient(address _router) external view returns (address);

  function getRouterOwner(address _router) external view returns (address);

  function getProposedRouterOwner(address _router) external view returns (address);

  function getProposedRouterOwnerTimestamp(address _router) external view returns (uint256);

  function maxRoutersPerTransfer() external view returns (uint256);

  function routerBalances(address _router, address _asset) external view returns (uint256);

  function getRouterApprovalForPortal(address _router) external view returns (bool);

  function initializeRouter(address _owner, address _recipient) external;

  function setRouterRecipient(address _router, address _recipient) external;

  function proposeRouterOwner(address _router, address _proposed) external;

  function acceptProposedRouterOwner(address _router) external;

  function addRouterLiquidityFor(
    uint256 _amount,
    address _local,
    address _router
  ) external payable;

  function addRouterLiquidity(uint256 _amount, address _local) external payable;

  function removeRouterLiquidityFor(
    TokenId memory _canonical,
    uint256 _amount,
    address payable _to,
    address _router
  ) external;

  function removeRouterLiquidity(TokenId memory _canonical, uint256 _amount, address payable _to) external;

  // ============ TOKEN_FACET ==============
  function adoptedToCanonical(address _adopted) external view returns (TokenId memory);

  function approvedAssets(TokenId calldata _canonical) external view returns (bool);
}

interface IERC20 {
    /**
     * @dev Emitted when value tokens are moved from one account (from) to
     * another (to).
     *
     * Note that value may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a spender for an owner is set by
     * a call to {approve}. value is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by account.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a value amount of tokens from the caller's account to to.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that spender will be
     * allowed to spend on behalf of owner through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a value amount of tokens as the allowance of spender over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a value amount of tokens from from to to using the
     * allowance mechanism. value is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
interface IWETH {
  function deposit() external payable;
  function approve(address guy, uint wad) external returns (bool);
}

/**
 * @title SimpleBridge
 * @notice Example of a cross-domain token transfer.
 */
contract FoodBridge {
  // The connext contract on the origin domain
  IConnext public immutable connext;

  constructor(address _connext) {
    connext = IConnext(_connext);
  }

  /**
   * @notice Transfers non-native assets from one chain to another.
   * @dev User should approve a spending allowance before calling this.
   * @param token Address of the token on this domain.
   * @param amount The amount to transfer.
   * @param recipient The destination address (e.g. a wallet).
   * @param destinationDomain The destination domain ID.
   * @param slippage The maximum amount of slippage the user will accept in BPS.
   * @param relayerFee The fee offered to relayers.
   */
  function xTransfer(
    address token,
    uint256 amount,
    address recipient,
    uint32 destinationDomain,
    uint256 slippage,
    uint256 relayerFee
  ) external payable {
    IERC20 _token = IERC20(token);

    require(
      _token.allowance(msg.sender, address(this)) >= amount,
      "User must approve amount"
    );

    // User sends funds to this contract
    _token.transferFrom(msg.sender, address(this), amount);

    // This contract approves transfer to Connext
    _token.approve(address(connext), amount);

    connext.xcall{value: relayerFee}(
      destinationDomain, // _destination: Domain ID of the destination chain
      recipient,         // _to: address receiving the funds on the destination
      token,             // _asset: address of the token contract
      msg.sender,        // _delegate: address that can revert or forceLocal on destination
      amount,            // _amount: amount of tokens to transfer
      slippage,          // _slippage: the maximum amount of slippage the user will accept in BPS (e.g. 30 = 0.3%)
      bytes("")          // _callData: empty bytes because we're only sending funds
    );  
  }

  /**
   * @notice Transfers native assets from one chain to another.
   * @param destinationUnwrapper Address of the Unwrapper contract on destination.
   * @param weth Address of the WETH contract on this domain.
   * @param amount The amount to transfer.
   * @param recipient The destination address (e.g. a wallet).
   * @param destinationDomain The destination domain ID.
   * @param slippage The maximum amount of slippage the user will accept in BPS.
   * @param relayerFee The fee offered to relayers.
   */
  function xTransferEth(
    address destinationUnwrapper,
    address weth,
    uint256 amount,
    address recipient,
    uint32 destinationDomain,
    uint256 slippage,
    uint256 relayerFee
  ) external payable {
    // Wrap ETH into WETH to send with the xcall
    IWETH(weth).deposit{value: amount}();

    // This contract approves transfer to Connext
    IWETH(weth).approve(address(connext), amount);

    // Encode the recipient address for calldata
    bytes memory callData = abi.encode(recipient);

    // xcall the Unwrapper contract to unwrap WETH into ETH on destination
    connext.xcall{value: relayerFee}(
      destinationDomain,    // _destination: Domain ID of the destination chain
      destinationUnwrapper, // _to: Unwrapper contract
      weth,                 // _asset: address of the WETH contract
      msg.sender,           // _delegate: address that can revert or forceLocal on destination
      amount,               // _amount: amount of tokens to transfer
      slippage,             // _slippage: the maximum amount of slippage the user will accept in BPS (e.g. 30 = 0.3%)
      callData              // _callData: calldata with encoded recipient address
    );  
  }
}