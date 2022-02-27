// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libraries/Utils.sol';
import {IComplication} from '../interfaces/IComplication.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title PrivateSaleComplication
 * @notice Complication that specifies an order that can only be executed by a specific address
 */
contract PrivateSaleComplication is IComplication, Ownable {
  uint256 public immutable PROTOCOL_FEE;
  uint256 public ERROR_BOUND; // error bound for prices in wei

  event NewErrorbound(uint256 errorBound);

  /**
   * @notice Constructor
   * @param _protocolFee protocol fee (200 --> 2%, 400 --> 4%)
   * @param _errorBound price error bound in wei
   */
  constructor(uint256 _protocolFee, uint256 _errorBound) {
    PROTOCOL_FEE = _protocolFee;
    ERROR_BOUND = _errorBound;
  }

  /**
   * @notice Check whether a taker accept order can be executed against an offer
   * @return (whether complication can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteOffer(OrderTypes.Taker calldata, OrderTypes.Maker calldata)
    external
    pure
    override
    returns (
      bool,
      uint256,
      uint256
    )
  {
    return (false, 0, 0);
  }

  /**
   * @notice Check whether a taker buy order can be executed against a maker listing
   * @param buy taker buy order
   * @param listing maker listing
   * @return (whether complication can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteListing(OrderTypes.Taker calldata buy, OrderTypes.Maker calldata listing)
    external
    view
    override
    returns (
      bool,
      uint256,
      uint256
    )
  {
    // Retrieve target buyer
    address targetBuyer = abi.decode(listing.params, (address));
    uint256 currentPrice = Utils.calculateCurrentPrice(listing);
    (uint256 startTime, uint256 endTime) = abi.decode(listing.startAndEndTimes, (uint256, uint256));
    (uint256 tokenId, uint256 amount) = abi.decode(listing.tokenInfo, (uint256, uint256));
    return (
      (targetBuyer == buy.taker &&
        Utils.arePricesWithinErrorBound(currentPrice, buy.price, ERROR_BOUND) &&
        tokenId == buy.tokenId &&
        startTime <= block.timestamp &&
        endTime >= block.timestamp),
      tokenId,
      amount
    );
  }

  /**
   * @notice Return protocol fee for this complication
   * @return protocol fee
   */
  function getProtocolFee() external view override returns (uint256) {
    return PROTOCOL_FEE;
  }

  function setErrorBound(uint256 _errorBound) external onlyOwner {
    ERROR_BOUND = _errorBound;
    emit NewErrorbound(_errorBound);
  }
}
