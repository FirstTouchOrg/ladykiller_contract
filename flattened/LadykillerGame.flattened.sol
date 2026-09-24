// Sources flattened with hardhat v2.26.3 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol@v1.5.0

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;

/// @notice The IVRFSubscriptionV2Plus interface defines the subscription
/// @notice related methods implemented by the V2Plus coordinator.
interface IVRFSubscriptionV2Plus {
  /**
   * @notice Add a consumer to a VRF subscription.
   * @param subId - ID of the subscription
   * @param consumer - New consumer which can use the subscription
   */
  function addConsumer(uint256 subId, address consumer) external;

  /**
   * @notice Remove a consumer from a VRF subscription.
   * @param subId - ID of the subscription
   * @param consumer - Consumer to remove from the subscription
   */
  function removeConsumer(uint256 subId, address consumer) external;

  /**
   * @notice Cancel a subscription
   * @param subId - ID of the subscription
   * @param to - Where to send the remaining LINK to
   */
  function cancelSubscription(uint256 subId, address to) external;

  /**
   * @notice Accept subscription owner transfer.
   * @param subId - ID of the subscription
   * @dev will revert if original owner of subId has
   * not requested that msg.sender become the new owner.
   */
  function acceptSubscriptionOwnerTransfer(
    uint256 subId
  ) external;

  /**
   * @notice Request subscription owner transfer.
   * @param subId - ID of the subscription
   * @param newOwner - proposed new owner of the subscription
   */
  function requestSubscriptionOwnerTransfer(uint256 subId, address newOwner) external;

  /**
   * @notice Create a VRF subscription.
   * @return subId - A unique subscription id.
   * @dev You can manage the consumer set dynamically with addConsumer/removeConsumer.
   * @dev Note to fund the subscription with LINK, use transferAndCall. For example
   * @dev  LINKTOKEN.transferAndCall(
   * @dev    address(COORDINATOR),
   * @dev    amount,
   * @dev    abi.encode(subId));
   * @dev Note to fund the subscription with Native, use fundSubscriptionWithNative. Be sure
   * @dev  to send Native with the call, for example:
   * @dev COORDINATOR.fundSubscriptionWithNative{value: amount}(subId);
   */
  function createSubscription() external returns (uint256 subId);

  /**
   * @notice Get a VRF subscription.
   * @param subId - ID of the subscription
   * @return balance - LINK balance of the subscription in juels.
   * @return nativeBalance - native balance of the subscription in wei.
   * @return reqCount - Requests count of subscription.
   * @return owner - owner of the subscription.
   * @return consumers - list of consumer address which are able to use this subscription.
   */
  function getSubscription(
    uint256 subId
  )
    external
    view
    returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers);

  /*
   * @notice Check to see if there exists a request commitment consumers
   * for all consumers and keyhashes for a given sub.
   * @param subId - ID of the subscription
   * @return true if there exists at least one unfulfilled request for the subscription, false
   * otherwise.
   */
  function pendingRequestExists(
    uint256 subId
  ) external view returns (bool);

  /**
   * @notice Paginate through all active VRF subscriptions.
   * @param startIndex index of the subscription to start from
   * @param maxCount maximum number of subscriptions to return, 0 to return all
   * @dev the order of IDs in the list is **not guaranteed**, therefore, if making successive calls, one
   * @dev should consider keeping the blockheight constant to ensure a holistic picture of the contract state
   */
  function getActiveSubscriptionIds(uint256 startIndex, uint256 maxCount) external view returns (uint256[] memory);

  /**
   * @notice Fund a subscription with native.
   * @param subId - ID of the subscription
   * @notice This method expects msg.value to be greater than or equal to 0.
   */
  function fundSubscriptionWithNative(
    uint256 subId
  ) external payable;
}


// File @chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol@v1.5.0

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.4;

// End consumer library.
library VRFV2PlusClient {
  // extraArgs will evolve to support new features
  bytes4 public constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

  struct ExtraArgsV1 {
    bool nativePayment;
  }

  struct RandomWordsRequest {
    bytes32 keyHash;
    uint256 subId;
    uint16 requestConfirmations;
    uint32 callbackGasLimit;
    uint32 numWords;
    bytes extraArgs;
  }

  function _argsToBytes(
    ExtraArgsV1 memory extraArgs
  ) internal pure returns (bytes memory bts) {
    return abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs);
  }
}


// File @chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol@v1.5.0

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;


// Interface that enables consumers of VRFCoordinatorV2Plus to be future-proof for upgrades
// This interface is supported by subsequent versions of VRFCoordinatorV2Plus
interface IVRFCoordinatorV2Plus is IVRFSubscriptionV2Plus {
  /**
   * @notice Request a set of random words.
   * @param req - a struct containing following fields for randomness request:
   * keyHash - Corresponds to a particular oracle job which uses
   * that key for generating the VRF proof. Different keyHash's have different gas price
   * ceilings, so you can select a specific one to bound your maximum per request cost.
   * subId  - The ID of the VRF subscription. Must be funded
   * with the minimum subscription balance required for the selected keyHash.
   * requestConfirmations - How many blocks you'd like the
   * oracle to wait before responding to the request. See SECURITY CONSIDERATIONS
   * for why you may want to request more. The acceptable range is
   * [minimumRequestBlockConfirmations, 200].
   * callbackGasLimit - How much gas you'd like to receive in your
   * fulfillRandomWords callback. Note that gasleft() inside fulfillRandomWords
   * may be slightly less than this amount because of gas used calling the function
   * (argument decoding etc.), so you may need to request slightly more than you expect
   * to have inside fulfillRandomWords. The acceptable range is
   * [0, maxGasLimit]
   * numWords - The number of uint256 random values you'd like to receive
   * in your fulfillRandomWords callback. Note these numbers are expanded in a
   * secure way by the VRFCoordinator from a single random value supplied by the oracle.
   * extraArgs - abi-encoded extra args
   * @return requestId - A unique identifier of the request. Can be used to match
   * a request to a response in fulfillRandomWords.
   */
  function requestRandomWords(
    VRFV2PlusClient.RandomWordsRequest calldata req
  ) external returns (uint256 requestId);
}


// File @openzeppelin/contracts/utils/Context.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts/access/Ownable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File @openzeppelin/contracts/access/Ownable2Step.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (access/Ownable2Step.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This extension of the {Ownable} contract includes a two-step mechanism to transfer
 * ownership, where the new owner must call {acceptOwnership} in order to replace the
 * old one. This can help prevent common mistakes, such as transfers of ownership to
 * incorrect accounts, or to contracts that are unable to interact with the
 * permission system.
 *
 * The initial owner is specified at deployment time in the constructor for `Ownable`. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     *
     * Setting `newOwner` to the zero address is allowed; this can be used to cancel an initiated ownership transfer.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}


// File @openzeppelin/contracts/utils/introspection/IERC165.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


// File @openzeppelin/contracts/interfaces/IERC165.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC165.sol)

pragma solidity >=0.4.16;


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
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
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


// File @openzeppelin/contracts/interfaces/IERC20.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

pragma solidity >=0.4.16;


// File @openzeppelin/contracts/interfaces/IERC1363.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1363.sol)

pragma solidity >=0.6.2;


/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}


// File @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity >=0.6.2;

/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// File @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;


/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Variant of {safeTransfer} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Variant of {safeTransferFrom} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}


// File @openzeppelin/contracts/utils/Pausable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}


// File contracts/FixedVRFConsumerBaseV2Plus.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity 0.8.24;



/// @notice VRF consumer with a coordinator that cannot be replaced after deployment.
/// @dev A new consumer must be deployed if Chainlink migrates its coordinator.
abstract contract FixedVRFConsumerBaseV2Plus is Ownable2Step {
    error OnlyCoordinatorCanFulfill(address have, address want);
    error ZeroAddress();
    error OwnershipRenunciationDisabled();

    IVRFCoordinatorV2Plus public immutable s_vrfCoordinator;

    constructor(address vrfCoordinator) Ownable(msg.sender) {
        if (vrfCoordinator == address(0)) revert ZeroAddress();
        s_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
    }

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        address coordinator = address(s_vrfCoordinator);
        if (msg.sender != coordinator) revert OnlyCoordinatorCanFulfill(msg.sender, coordinator);
        fulfillRandomWords(requestId, randomWords);
    }
}


// File @openzeppelin/contracts/utils/ReentrancyGuard.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}


// File contracts/LadykillerGame.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity 0.8.24;







/// @title Ladykiller on-chain chase game
/// @notice Manages one active round at a time, one Chainlink VRF request per funded round,
///         pooled solvency, settlement, claims, timeout cancellation and refunds.
/// @dev This is an initial implementation and must be audited before mainnet use.
contract LadykillerGame is FixedVRFConsumerBaseV2Plus, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant MALE_COUNT = 51;
    uint8 public constant SUCCESSFUL_MALE_COUNT = 3;
    uint8 public constant RESULT_COUNT = 49;
    uint8 public constant RULES_VERSION = 3;
    uint40 public constant BETTING_DURATION = 45 seconds;
    uint40 public constant VRF_FINAL_TIMEOUT = 24 hours;
    uint32 public constant NUM_RANDOM_WORDS = 1;
    uint256 public constant BET_OPTION_COUNT = 12;
    uint256 public constant MAX_BETS_PER_TRANSACTION = BET_OPTION_COUNT;
    uint256 public constant MAX_CLAIMS_PER_TRANSACTION = 50;
    uint256 public constant MAX_REFUNDS_PER_TRANSACTION = 50;
    uint256 public constant MAX_PLAYER_ROUNDS_PAGE = 100;

    enum RoundState {
        NONE,
        BETTING,
        WAITING_RANDOMNESS,
        RANDOM_READY,
        SETTLED,
        CANCELLED,
        SKIPPED
    }

    enum BetOption {
        RANGE_1_5,
        RANGE_6_10,
        RANGE_11_15,
        RANGE_16_20,
        RANGE_21_25,
        RANGE_26_30,
        RANGE_31_35,
        RANGE_36_40,
        RANGE_41_45,
        RANGE_46_49,
        DAY,
        NIGHT
    }

    struct BetInput {
        BetOption option;
        uint256 amount;
    }

    struct Round {
        RoundState state;
        uint8 rulesVersion;
        uint8[3] successfulMaleIds;
        uint8 resultPosition;
        uint8 winningMaleId;
        uint40 createdAt;
        uint40 bettingStart;
        uint40 bettingDeadline;
        uint40 randomnessRequestedAt;
        uint256 randomWord;
        uint256 totalBets;
        uint256 requiredReserve;
        uint256 totalPayout;
    }

    struct RequestInfo {
        uint256 roundId;
        bool fulfilled;
    }

    error UnauthorizedKeeper();
    error InvalidAddress();
    error InvalidAmount();
    error BelowMinimumBet(uint256 minimum, uint256 provided);
    error InvalidTokenDecimals(uint8 decimals);
    error InvalidDayBetPrecision();
    error InvalidState(RoundState expected, RoundState actual);
    error BettingClosed();
    error BettingStillOpen();
    error TooManyBets();
    error TooManyClaims();
    error InvalidRefundBatchSize();
    error RefundNotDeferred();
    error InsufficientBankroll(uint256 required, uint256 available);
    error UnsupportedFeeOnTransferToken();
    error NothingToClaim();
    error AlreadyClaimed();
    error TimeoutNotReached();
    error RequestWindowExpired();
    error RandomnessAlreadyAvailable();
    error InvalidVrfConfiguration();
    error ActiveRoundExists(uint256 roundId);
    error EmptyRound();
    error RoundHasBets();

    IERC20 public immutable wagerToken;
    uint256 public immutable minimumBet;
    bytes32 public immutable vrfKeyHash;
    uint256 public immutable vrfSubscriptionId;
    uint32 public immutable vrfCallbackGasLimit;
    uint16 public immutable vrfRequestConfirmations;
    uint40 public immutable vrfTimeout;
    bool public immutable payVrfWithNative;

    uint256 public nextRoundId = 1;
    uint256 public activeRoundId;
    uint256 public totalActiveReserve;
    uint256 public lockedPlayerPayouts;
    uint256 public safetyBuffer;

    uint256 public keeperEpoch = 1;
    mapping(address => uint256) private _keeperEpoch;
    mapping(uint256 => Round) private _rounds;
    mapping(uint256 => RequestInfo) public vrfRequests;

    mapping(uint256 => mapping(address => mapping(BetOption => uint256))) private _bets;
    mapping(uint256 => mapping(address => uint256)) public totalBetByPlayer;
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(uint256 => mapping(address => bool)) public refunded;
    mapping(uint256 => mapping(address => bool)) public refundDeferred;
    mapping(uint256 => uint256) public refundCursor;
    mapping(address => uint256[]) private _playerRounds;
    mapping(uint256 => address[]) private _roundPlayers;

    mapping(uint256 => mapping(BetOption => uint256)) public optionBetTotals;

    event KeeperUpdated(address indexed keeper, bool allowed);
    event SafetyBufferUpdated(uint256 oldBuffer, uint256 newBuffer);
    event BankrollFunded(address indexed funder, uint256 amount);
    event FreeFundsWithdrawn(address indexed recipient, uint256 amount);
    event RoundStarted(uint256 indexed roundId, uint40 bettingStart, uint40 bettingDeadline);
    event BetSelectionPlaced(
        address indexed player,
        uint256 indexed roundId,
        BetOption option,
        uint256 amount
    );
    event BetsPlaced(address indexed player, uint256 indexed roundId, uint256 amount, uint256 newReserve);
    event RoundClosed(uint256 indexed roundId, uint256 indexed requestId);
    event RoundSkipped(uint256 indexed roundId);
    event ResultRandomnessReady(uint256 indexed roundId, uint256 indexed requestId, uint256 randomWord);
    event RoundSettled(
        uint256 indexed roundId,
        uint8 resultPosition,
        uint8 winningMaleId,
        uint8[3] successfulMaleIds,
        uint256 totalPayout
    );
    event Claimed(address indexed player, uint256 indexed roundId, uint256 amount);
    event RoundCancelled(uint256 indexed roundId, uint256 refundLiability);
    event StalledRoundReleased(uint256 indexed roundId);
    event Refunded(address indexed player, uint256 indexed roundId, uint256 amount);
    event RefundDeferred(address indexed player, uint256 indexed roundId, uint256 amount);
    event RandomnessFulfillmentIgnored(uint256 indexed requestId, uint256 indexed roundId);

    modifier onlyKeeper() {
        if (!keepers(msg.sender) && msg.sender != owner()) revert UnauthorizedKeeper();
        _;
    }

    constructor(
        address wagerTokenAddress,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint40 timeout,
        bool nativePayment,
        uint256 initialSafetyBuffer,
        address initialKeeper
    ) FixedVRFConsumerBaseV2Plus(vrfCoordinator) {
        if (
            wagerTokenAddress == address(0) || vrfCoordinator == address(0)
                || initialKeeper == address(0) || initialKeeper == msg.sender
        ) revert InvalidAddress();
        if (callbackGasLimit == 0 || requestConfirmations == 0 || timeout == 0) {
            revert InvalidVrfConfiguration();
        }

        wagerToken = IERC20(wagerTokenAddress);
        uint8 tokenDecimals = IERC20Metadata(wagerTokenAddress).decimals();
        if (tokenDecimals > 77) revert InvalidTokenDecimals(tokenDecimals);
        minimumBet = 10 ** uint256(tokenDecimals);
        vrfKeyHash = keyHash;
        vrfSubscriptionId = subscriptionId;
        vrfCallbackGasLimit = callbackGasLimit;
        vrfRequestConfirmations = requestConfirmations;
        vrfTimeout = timeout;
        payVrfWithNative = nativePayment;
        safetyBuffer = initialSafetyBuffer;
        _keeperEpoch[initialKeeper] = keeperEpoch;
        emit KeeperUpdated(initialKeeper, true);
    }

    /// @notice Creates a round and immediately opens its fixed betting window.
    /// @dev No randomness is requested until betting has closed.
    function startRound() external onlyKeeper whenNotPaused returns (uint256 roundId) {
        if (activeRoundId != 0) revert ActiveRoundExists(activeRoundId);
        roundId = nextRoundId++;
        activeRoundId = roundId;
        Round storage round = _rounds[roundId];
        uint40 bettingStart = uint40(block.timestamp);
        uint40 bettingDeadline = uint40(block.timestamp + BETTING_DURATION);

        round.state = RoundState.BETTING;
        round.rulesVersion = RULES_VERSION;
        round.createdAt = bettingStart;
        round.bettingStart = bettingStart;
        round.bettingDeadline = bettingDeadline;

        emit RoundStarted(roundId, bettingStart, bettingDeadline);
    }

    /// @notice Places one or more range/day/night bets with independent amounts in one transaction.
    function placeBets(uint256 roundId, BetInput[] calldata inputs) external nonReentrant whenNotPaused {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (block.timestamp >= round.bettingDeadline) revert BettingClosed();
        if (inputs.length == 0 || inputs.length > MAX_BETS_PER_TRANSACTION) revert TooManyBets();

        uint256 totalAmount;
        for (uint256 i; i < inputs.length; ++i) {
            BetInput calldata input = inputs[i];
            if (input.amount < minimumBet) revert BelowMinimumBet(minimumBet, input.amount);
            if (input.option == BetOption.DAY) {
                // Ensures aggregate 1.9x liability exactly equals the sum of
                // per-player claims, leaving no permanently locked rounding dust.
                if (input.amount % 10 != 0) revert InvalidDayBetPrecision();
            }
            _bets[roundId][msg.sender][input.option] += input.amount;
            optionBetTotals[roundId][input.option] += input.amount;
            totalAmount += input.amount;
            emit BetSelectionPlaced(msg.sender, roundId, input.option, input.amount);
        }

        uint256 oldBalance = wagerToken.balanceOf(address(this));
        wagerToken.safeTransferFrom(msg.sender, address(this), totalAmount);
        uint256 newBalance = wagerToken.balanceOf(address(this));
        if (newBalance - oldBalance != totalAmount) revert UnsupportedFeeOnTransferToken();

        round.totalBets += totalAmount;
        if (totalBetByPlayer[roundId][msg.sender] == 0) {
            _playerRounds[msg.sender].push(roundId);
            _roundPlayers[roundId].push(msg.sender);
        }
        totalBetByPlayer[roundId][msg.sender] += totalAmount;

        uint256 oldReserve = round.requiredReserve;
        uint256 newReserve = _calculateRequiredReserve(roundId);
        if (round.totalBets > newReserve) newReserve = round.totalBets;
        uint256 projectedActiveReserve = totalActiveReserve - oldReserve + newReserve;
        uint256 requiredBalance = lockedPlayerPayouts + projectedActiveReserve + safetyBuffer;
        if (newBalance < requiredBalance) revert InsufficientBankroll(requiredBalance, newBalance);

        round.requiredReserve = newReserve;
        totalActiveReserve = projectedActiveReserve;
        emit BetsPlaced(msg.sender, roundId, totalAmount, newReserve);
    }

    /// @notice Closes betting after the deadline and requests result randomness.
    /// @dev Permissionless so a keeper outage cannot permanently stall a round.
    function closeRound(uint256 roundId) external returns (uint256 requestId) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (block.timestamp < round.bettingDeadline) revert BettingStillOpen();
        if (block.timestamp >= uint256(round.bettingDeadline) + vrfTimeout) revert RequestWindowExpired();
        if (round.totalBets == 0) revert EmptyRound();

        round.state = RoundState.WAITING_RANDOMNESS;
        round.randomnessRequestedAt = uint40(block.timestamp);
        requestId = _requestRandomness(roundId);
        emit RoundClosed(roundId, requestId);
    }

    /// @notice Ends an expired round with no bets without paying for VRF.
    function closeEmptyRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (block.timestamp < round.bettingDeadline) revert BettingStillOpen();
        if (round.totalBets != 0) revert RoundHasBets();

        round.state = RoundState.SKIPPED;
        if (activeRoundId == roundId) activeRoundId = 0;
        emit RoundSkipped(roundId);
    }

    /// @notice Performs both deterministic shuffles from the single VRF word and settles the round.
    /// @dev Permissionless and retryable. Complex work is intentionally outside the VRF callback.
    function finalizeRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.RANDOM_READY) {
            revert InvalidState(RoundState.RANDOM_READY, round.state);
        }

        (uint8[3] memory successfulMaleIds, uint8 resultPosition, uint8 winningMaleId) =
            _deriveResult(roundId, round.randomWord);
        uint256 payout = _payoutForOutcome(roundId, resultPosition);

        round.state = RoundState.SETTLED;
        round.successfulMaleIds = successfulMaleIds;
        round.resultPosition = resultPosition;
        round.winningMaleId = winningMaleId;
        round.totalPayout = payout;

        totalActiveReserve -= round.requiredReserve;
        round.requiredReserve = 0;
        lockedPlayerPayouts += payout;
        if (activeRoundId == roundId) activeRoundId = 0;

        emit RoundSettled(roundId, resultPosition, winningMaleId, successfulMaleIds, payout);
    }

    /// @notice Claims the caller's winnings for a settled round.
    function claim(uint256 roundId) external nonReentrant returns (uint256 amount) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.SETTLED) revert InvalidState(RoundState.SETTLED, round.state);
        if (claimed[roundId][msg.sender]) revert AlreadyClaimed();

        amount = _claimable(roundId, msg.sender, round.resultPosition);
        if (amount == 0) revert NothingToClaim();

        claimed[roundId][msg.sender] = true;
        lockedPlayerPayouts -= amount;
        wagerToken.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, roundId, amount);
    }

    /// @notice Claims winnings from multiple settled rounds and transfers the aggregate once.
    /// @dev Invalid, losing, duplicate and previously claimed rounds are skipped.
    function claimMany(uint256[] calldata roundIds) external nonReentrant returns (uint256 totalAmount) {
        if (roundIds.length == 0 || roundIds.length > MAX_CLAIMS_PER_TRANSACTION) revert TooManyClaims();

        for (uint256 i; i < roundIds.length; ++i) {
            uint256 roundId = roundIds[i];
            Round storage round = _rounds[roundId];
            if (round.state != RoundState.SETTLED || claimed[roundId][msg.sender]) continue;

            uint256 amount = _claimable(roundId, msg.sender, round.resultPosition);
            if (amount == 0) continue;
            claimed[roundId][msg.sender] = true;
            totalAmount += amount;
            emit Claimed(msg.sender, roundId, amount);
        }

        if (totalAmount == 0) revert NothingToClaim();
        lockedPlayerPayouts -= totalAmount;
        wagerToken.safeTransfer(msg.sender, totalAmount);
    }

    /// @notice Cancels a funded round that never successfully requested VRF.
    /// @dev A successful closeRound and this cancellation are mutually exclusive.
    function cancelUnrequestedRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (round.totalBets == 0) revert EmptyRound();
        if (block.timestamp < uint256(round.bettingDeadline) + vrfTimeout) revert TimeoutNotReached();
        _cancelRound(roundId, round);
    }

    /// @notice Frees the active slot while an old VRF request continues waiting.
    /// @dev The original request and its full payout reserve remain live.
    function releaseStalledRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.WAITING_RANDOMNESS) {
            revert InvalidState(RoundState.WAITING_RANDOMNESS, round.state);
        }
        if (block.timestamp < uint256(round.randomnessRequestedAt) + vrfTimeout) revert TimeoutNotReached();
        if (activeRoundId == roundId) {
            activeRoundId = 0;
            emit StalledRoundReleased(roundId);
        }
    }

    /// @notice Refunds a request that is still unanswered at the fixed final deadline.
    /// @dev The deadline, rather than the caller or transaction ordering after it, decides validity.
    function cancelTimedOutRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.WAITING_RANDOMNESS) revert RandomnessAlreadyAvailable();
        if (block.timestamp < uint256(round.randomnessRequestedAt) + VRF_FINAL_TIMEOUT) revert TimeoutNotReached();
        _cancelRound(roundId, round);
    }

    /// @notice Returns principal to the next contiguous batch of players after a whole-round cancellation.
    /// @dev Anyone may advance the cursor, but no caller can select recipients or refund amounts.
    function refundBatch(uint256 roundId, uint256 maxPlayers) external nonReentrant returns (uint256 count) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.CANCELLED) revert InvalidState(RoundState.CANCELLED, round.state);
        if (maxPlayers == 0 || maxPlayers > MAX_REFUNDS_PER_TRANSACTION) revert InvalidRefundBatchSize();
        uint256 cursor = refundCursor[roundId];
        uint256 length = _roundPlayers[roundId].length;
        if (cursor == length) revert NothingToClaim();
        uint256 end = cursor + maxPlayers;
        if (end > length) end = length;

        refundCursor[roundId] = end;
        for (uint256 i = cursor; i < end; ++i) {
            address player = _roundPlayers[roundId][i];
            uint256 amount = totalBetByPlayer[roundId][player];
            if (wagerToken.trySafeTransfer(player, amount)) {
                refunded[roundId][player] = true;
                lockedPlayerPayouts -= amount;
                emit Refunded(player, roundId, amount);
            } else {
                refundDeferred[roundId][player] = true;
                emit RefundDeferred(player, roundId, amount);
            }
        }
        count = end - cursor;
    }

    /// @notice Allows only a failed recipient to retry receiving their unchanged principal.
    function claimDeferredRefund(uint256 roundId) external nonReentrant returns (uint256 amount) {
        if (!refundDeferred[roundId][msg.sender]) revert RefundNotDeferred();
        amount = totalBetByPlayer[roundId][msg.sender];
        refundDeferred[roundId][msg.sender] = false;
        refunded[roundId][msg.sender] = true;
        lockedPlayerPayouts -= amount;
        wagerToken.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, roundId, amount);
    }

    function roundPlayerCount(uint256 roundId) external view returns (uint256) {
        return _roundPlayers[roundId].length;
    }

    /// @notice Adds tokens to the shared bankroll.
    function fundBankroll(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 oldBalance = wagerToken.balanceOf(address(this));
        wagerToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = wagerToken.balanceOf(address(this)) - oldBalance;
        if (received != amount) revert UnsupportedFeeOnTransferToken();
        emit BankrollFunded(msg.sender, amount);
    }

    /// @notice Withdraws only funds not reserved for active rounds or player claims.
    function withdrawFreeFunds(address recipient, uint256 amount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        uint256 available = withdrawableFunds();
        if (amount > available) revert InsufficientBankroll(amount, available);
        wagerToken.safeTransfer(recipient, amount);
        emit FreeFundsWithdrawn(recipient, amount);
    }

    function setKeeper(address keeper, bool allowed) external onlyOwner {
        if (keeper == address(0)) revert InvalidAddress();
        _keeperEpoch[keeper] = allowed ? keeperEpoch : 0;
        emit KeeperUpdated(keeper, allowed);
    }

    function keepers(address keeper) public view returns (bool) {
        return keeper != address(0) && _keeperEpoch[keeper] == keeperEpoch;
    }

    /// @dev All keeper grants from the previous owner expire only when the new owner accepts.
    function acceptOwnership() public override {
        super.acceptOwnership();
        ++keeperEpoch;
    }

    function setSafetyBuffer(uint256 newBuffer) external onlyOwner {
        uint256 oldBuffer = safetyBuffer;
        safetyBuffer = newBuffer;
        emit SafetyBufferUpdated(oldBuffer, newBuffer);
    }

    /// @notice Pauses only new rounds and new bets. Close, settle, claim and refund remain available.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return _rounds[roundId];
    }

    function getRoundLifecycle(uint256 roundId)
        external
        view
        returns (RoundState state, uint40 bettingDeadline, uint40 randomnessRequestedAt, uint256 totalBets)
    {
        Round storage round = _rounds[roundId];
        return (round.state, round.bettingDeadline, round.randomnessRequestedAt, round.totalBets);
    }

    /// @notice Reproduces the two shuffles for public verification of a revealed VRF word.
    function previewResult(uint256 roundId, uint256 vrfSeed)
        external
        pure
        returns (uint8[3] memory successfulMaleIds, uint8 resultPosition, uint8 winningMaleId)
    {
        return _deriveResult(roundId, vrfSeed);
    }

    function getBet(uint256 roundId, address player, BetOption option) external view returns (uint256) {
        return _bets[roundId][player][option];
    }

    function getPlayerBets(uint256 roundId, address player) external view returns (uint256[12] memory amounts) {
        for (uint8 optionIndex; optionIndex < BET_OPTION_COUNT; ++optionIndex) {
            amounts[optionIndex] = _bets[roundId][player][BetOption(optionIndex)];
        }
    }

    function getRoundOptionTotals(uint256 roundId) external view returns (uint256[12] memory amounts) {
        for (uint8 optionIndex; optionIndex < BET_OPTION_COUNT; ++optionIndex) {
            amounts[optionIndex] = optionBetTotals[roundId][BetOption(optionIndex)];
        }
    }

    function playerRoundCount(address player) external view returns (uint256) {
        return _playerRounds[player].length;
    }

    /// @notice Returns an ascending slice of rounds recorded directly when the player first bet.
    function getPlayerRounds(address player, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory roundIds)
    {
        uint256 count = _playerRounds[player].length;
        if (offset >= count || limit == 0) return new uint256[](0);
        if (limit > MAX_PLAYER_ROUNDS_PAGE) limit = MAX_PLAYER_ROUNDS_PAGE;
        uint256 end = offset + limit;
        if (end > count) end = count;
        roundIds = new uint256[](end - offset);
        for (uint256 i; i < roundIds.length; ++i) roundIds[i] = _playerRounds[player][offset + i];
    }

    function claimable(uint256 roundId, address player) external view returns (uint256) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.SETTLED || claimed[roundId][player]) return 0;
        return _claimable(roundId, player, round.resultPosition);
    }

    function claimableBatch(address player, uint256[] calldata roundIds)
        external
        view
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        if (roundIds.length > MAX_PLAYER_ROUNDS_PAGE) revert TooManyClaims();
        amounts = new uint256[](roundIds.length);
        for (uint256 i; i < roundIds.length; ++i) {
            uint256 roundId = roundIds[i];
            Round storage round = _rounds[roundId];
            if (round.state != RoundState.SETTLED || claimed[roundId][player]) continue;
            uint256 amount = _claimable(roundId, player, round.resultPosition);
            amounts[i] = amount;
            totalAmount += amount;
        }
    }

    function withdrawableFunds() public view returns (uint256) {
        uint256 balance = wagerToken.balanceOf(address(this));
        uint256 unavailable = lockedPlayerPayouts + totalActiveReserve + safetyBuffer;
        return balance > unavailable ? balance - unavailable : 0;
    }

    /// @notice Previews a batch using the current on-chain state. The final transaction rechecks solvency.
    function quoteBets(uint256 roundId, BetInput[] calldata inputs)
        external
        view
        returns (bool accepted, uint256 totalAmount, uint256 newReserve, uint256 projectedBalance)
    {
        Round storage round = _rounds[roundId];
        if (paused() || round.state != RoundState.BETTING || block.timestamp >= round.bettingDeadline) {
            return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
        }
        if (inputs.length == 0 || inputs.length > MAX_BETS_PER_TRANSACTION) {
            return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
        }

        uint256[12] memory optionAdds;
        for (uint256 i; i < inputs.length; ++i) {
            BetInput calldata input = inputs[i];
            if (input.amount < minimumBet) {
                return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
            }
            if (input.option == BetOption.DAY) {
                if (input.amount % 10 != 0) {
                    return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
                }
            }
            optionAdds[uint8(input.option)] += input.amount;
            totalAmount += input.amount;
        }

        newReserve = _calculateRequiredReserveWithAdds(roundId, optionAdds);
        uint256 projectedRoundBets = round.totalBets + totalAmount;
        if (projectedRoundBets > newReserve) newReserve = projectedRoundBets;
        projectedBalance = wagerToken.balanceOf(address(this)) + totalAmount;
        uint256 projectedActiveReserve = totalActiveReserve - round.requiredReserve + newReserve;
        accepted = projectedBalance >= lockedPlayerPayouts + projectedActiveReserve + safetyBuffer;
    }

    /// @dev The callback only stores the VRF word. Both shuffles run in finalizeRound.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        RequestInfo storage request = vrfRequests[requestId];
        uint256 roundId = request.roundId;
        if (roundId == 0 || request.fulfilled || randomWords.length == 0) {
            emit RandomnessFulfillmentIgnored(requestId, roundId);
            return;
        }

        request.fulfilled = true;
        Round storage round = _rounds[roundId];
        if (
            round.state == RoundState.WAITING_RANDOMNESS
                && block.timestamp < uint256(round.randomnessRequestedAt) + VRF_FINAL_TIMEOUT
        ) {
            round.randomWord = randomWords[0];
            round.state = RoundState.RANDOM_READY;
            emit ResultRandomnessReady(roundId, requestId, randomWords[0]);
            return;
        }

        emit RandomnessFulfillmentIgnored(requestId, roundId);
    }

    function _cancelRound(uint256 roundId, Round storage round) private {
        round.state = RoundState.CANCELLED;
        totalActiveReserve -= round.requiredReserve;
        round.requiredReserve = 0;
        lockedPlayerPayouts += round.totalBets;
        if (activeRoundId == roundId) activeRoundId = 0;
        emit RoundCancelled(roundId, round.totalBets);
    }

    function _requestRandomness(uint256 roundId) private returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: NUM_RANDOM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: payVrfWithNative})
                )
            })
        );
        vrfRequests[requestId] = RequestInfo({roundId: roundId, fulfilled: false});
    }

    function _calculateRequiredReserve(uint256 roundId) private view returns (uint256 maximum) {
        for (uint8 optionIndex; optionIndex < uint8(BetOption.DAY); ++optionIndex) {
            BetOption rangeOption = BetOption(optionIndex);
            uint256 rangePayout = optionBetTotals[roundId][rangeOption] * _rangeReturnMultiplier(rangeOption);
            if (rangePayout > maximum) maximum = rangePayout;
        }
        uint256 dayPayout = (optionBetTotals[roundId][BetOption.DAY] * 19) / 10;
        uint256 nightPayout = optionBetTotals[roundId][BetOption.NIGHT] * 2;
        maximum += dayPayout > nightPayout ? dayPayout : nightPayout;
    }

    function _calculateRequiredReserveWithAdds(uint256 roundId, uint256[12] memory optionAdds)
        private
        view
        returns (uint256 maximum)
    {
        for (uint8 optionIndex; optionIndex < uint8(BetOption.DAY); ++optionIndex) {
            BetOption rangeOption = BetOption(optionIndex);
            uint256 rangeTotal = optionBetTotals[roundId][rangeOption] + optionAdds[optionIndex];
            uint256 rangePayout = rangeTotal * _rangeReturnMultiplier(rangeOption);
            if (rangePayout > maximum) maximum = rangePayout;
        }
        uint256 dayTotal = optionBetTotals[roundId][BetOption.DAY] + optionAdds[uint8(BetOption.DAY)];
        uint256 nightTotal = optionBetTotals[roundId][BetOption.NIGHT] + optionAdds[uint8(BetOption.NIGHT)];
        uint256 dayPayout = (dayTotal * 19) / 10;
        uint256 nightPayout = nightTotal * 2;
        maximum += dayPayout > nightPayout ? dayPayout : nightPayout;
    }

    function _payoutForOutcome(uint256 roundId, uint8 position) private view returns (uint256) {
        BetOption rangeOption = _rangeOptionForPosition(position);
        uint256 payout = optionBetTotals[roundId][rangeOption] * _totalReturnMultiplier(position);
        payout += position % 2 == 1
            ? (optionBetTotals[roundId][BetOption.DAY] * 19) / 10
            : optionBetTotals[roundId][BetOption.NIGHT] * 2;
        return payout;
    }

    function _claimable(uint256 roundId, address player, uint8 position) private view returns (uint256) {
        BetOption rangeOption = _rangeOptionForPosition(position);
        uint256 amount = _bets[roundId][player][rangeOption] * _totalReturnMultiplier(position);
        amount += position % 2 == 1
            ? (_bets[roundId][player][BetOption.DAY] * 19) / 10
            : _bets[roundId][player][BetOption.NIGHT] * 2;
        return amount;
    }

    /// @dev First shuffle selects three successful males. The second shuffle determines
    ///      which selected male appears first and therefore the chase duration (1-49).
    function _deriveResult(uint256 roundId, uint256 vrfSeed)
        private
        pure
        returns (uint8[3] memory successfulMaleIds, uint8 resultPosition, uint8 winningMaleId)
    {
        uint256 selectionSeed = uint256(keccak256(abi.encode(vrfSeed, roundId, "MALE_SELECTION")));
        uint8[51] memory selectionOrder = _orderedMales();
        _shuffle(selectionOrder, selectionSeed);
        successfulMaleIds = [selectionOrder[0], selectionOrder[1], selectionOrder[2]];

        uint256 chaseSeed = uint256(keccak256(abi.encode(vrfSeed, roundId, "CHASE_ORDER")));
        uint8[51] memory chaseOrder = _orderedMales();
        _shuffle(chaseOrder, chaseSeed);

        for (uint8 i; i < MALE_COUNT; ++i) {
            uint8 maleId = chaseOrder[i];
            if (
                maleId == successfulMaleIds[0] || maleId == successfulMaleIds[1]
                    || maleId == successfulMaleIds[2]
            ) {
                return (successfulMaleIds, i + 1, maleId);
            }
        }
        assert(false);
        return (successfulMaleIds, 0, 0);
    }

    function _orderedMales() private pure returns (uint8[51] memory males) {
        for (uint8 i; i < MALE_COUNT; ++i) males[i] = i + 1;
    }

    function _shuffle(uint8[51] memory values, uint256 seed) private pure {
        for (uint256 i = MALE_COUNT - 1; i > 0; --i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 j = _uniform(entropy, i + 1);
            (values[i], values[j]) = (values[j], values[i]);
        }
    }

    function _rangeOptionForPosition(uint8 position) private pure returns (BetOption) {
        if (position <= 5) return BetOption.RANGE_1_5;
        if (position <= 10) return BetOption.RANGE_6_10;
        if (position <= 15) return BetOption.RANGE_11_15;
        if (position <= 20) return BetOption.RANGE_16_20;
        if (position <= 25) return BetOption.RANGE_21_25;
        if (position <= 30) return BetOption.RANGE_26_30;
        if (position <= 35) return BetOption.RANGE_31_35;
        if (position <= 40) return BetOption.RANGE_36_40;
        if (position <= 45) return BetOption.RANGE_41_45;
        return BetOption.RANGE_46_49;
    }

    function _totalReturnMultiplier(uint8 position) private pure returns (uint256) {
        return _rangeReturnMultiplier(_rangeOptionForPosition(position));
    }

    function _rangeReturnMultiplier(BetOption rangeOption) private pure returns (uint256) {
        if (rangeOption == BetOption.RANGE_1_5) return 3;
        if (rangeOption == BetOption.RANGE_6_10) return 4;
        if (rangeOption == BetOption.RANGE_11_15) return 5;
        if (rangeOption == BetOption.RANGE_16_20) return 6;
        if (rangeOption == BetOption.RANGE_21_25) return 9;
        if (rangeOption == BetOption.RANGE_26_30) return 13;
        if (rangeOption == BetOption.RANGE_31_35) return 21;
        if (rangeOption == BetOption.RANGE_36_40) return 41;
        if (rangeOption == BetOption.RANGE_41_45) return 111;
        return 801;
    }

    /// @dev Rejection sampling avoids modulo bias.
    function _uniform(uint256 entropy, uint256 upperBound) private pure returns (uint256) {
        uint256 minimum = type(uint256).max - (type(uint256).max % upperBound);
        while (entropy >= minimum) entropy = uint256(keccak256(abi.encode(entropy)));
        return entropy % upperBound;
    }
}
