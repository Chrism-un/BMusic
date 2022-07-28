// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface BoleroABI {
    function management() external view returns (address);

    function rewards() external view returns (address);
}

interface PaymentSplitterABI {
    function releaseToken(address _want) external;
}

interface IBoleroArtistToken {
    function approve(address spender, uint256 amount) external;

    function balanceOf(address _owner) external view returns (uint256);

    function transferFromICO(
        address _from,
        address _to,
        uint256 _value
    ) external;

    function isAvailableToTrade() external view returns (bool);

    function isEmergencyPause() external view returns (bool);
}

interface IBoleroArtist {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function approve(address spender, uint256 amount) external returns (bool);

    function artistPayment() external view returns (address);

    function isWithPaymentSplitter() external view returns (bool);
}

contract BoleroArtistICO {
    using SafeERC20 for IERC20;

    IBoleroArtist public boleroArtist;
    IBoleroArtistToken public boleroToken;

    uint256 public constant MAXIMUM_PERCENT = 10000;
    uint256 public pricePerShare = 0;
    uint256 public shareForBolero = 0;
    uint256 public shareForArtist = 0;
    uint256 public boleroTreasure = 0;
    uint256 public artistTreasure = 0;
    address public bolero = address(0);
    uint256 public underlyingDecimals = 0;
    IERC20Metadata public want;

    modifier onlyBoleroOrManagement() {
        require(
            address(msg.sender) == bolero ||
                address(msg.sender) == BoleroABI(bolero).management(),
            "!authorized"
        );
        _;
    }

    event SetPricePerShare(uint256 newPrice);
    event SetShares(uint256 shareForBolero, uint256 shareForArtist);

    /*******************************************************************************
     ** @param _shareForBolero: % of share for Bolero on the ICO.
     ** @param _shareForArtist: % of share for the artist on the ICO.
     ** @param _initialPricePerShare: the initial price per share.
     *******************************************************************************/
    constructor(
        address _bolero,
        address _boleroArtist,
        address _icoWantToken,
        uint256[2] memory _shares,
        uint256 _initialPricePerShare
    ) {
        bolero = _bolero;
        boleroToken = IBoleroArtistToken(msg.sender);
        boleroArtist = IBoleroArtist(_boleroArtist);
        _setShares(_shares[0], _shares[1]);
        _setPricePerShare(_initialPricePerShare);
        want = IERC20Metadata(_icoWantToken);
        underlyingDecimals = IERC20Metadata(_icoWantToken).decimals();
    }

    /*******************************************************************************
     ** @notice
     **  While on the initial coin offering, anyone can buy a share of the Bolero
     **      token. The price is set by Bolero and the amount is splitted between
     **      the artist and bolero.
     **      If we are at the end of the sale and the buyer try to buy more token
     **      than available, limit the share to the available balance and adjust
     **      the amount of underlying token to use to the correct value.
     ** @param from: address which will receive the BoleroTokens
     ** @param amount: amount of underlying the sender wants to pay.
     *******************************************************************************/
    function buyShare(address from, uint256 amount) public returns (uint256) {
        require(boleroToken.isEmergencyPause() == false, "!emergency");
        require(!boleroToken.isAvailableToTrade(), "no longer available");
        uint256 forSponsor = (((amount * 1e18) / pricePerShare) * (10**underlyingDecimals)) * (10**underlyingDecimals);


     if (forSponsor > boleroToken.balanceOf(address(this))) {
            forSponsor = boleroToken.balanceOf(address(this));
            amount = forSponsor * pricePerShare;
        }

        uint256 amountForBolero = (amount * shareForBolero) / MAXIMUM_PERCENT;
        uint256 amountForArtist = amount - amountForBolero;

        boleroTreasure += amountForBolero;
        artistTreasure += amountForArtist;
        require(
            want.transferFrom(
                msg.sender,
                address(this),
                amountForArtist + amountForBolero
            )
        );
        boleroToken.transferFromICO(address(this), from, forSponsor);
        return (forSponsor);
    }

    /*******************************************************************************
     ** @notice
     **  Simulate a buyShare
     ** @param from: address which will receive the BoleroTokens
     ** @param amount: amount of underlying the sender wants to pay.
     *******************************************************************************/
    function estimateBuyShare(uint256 amount)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 forSponsor = (((amount * 1e18) / pricePerShare) *
            (10**underlyingDecimals)) * (10**underlyingDecimals);
        if (forSponsor > boleroToken.balanceOf(address(this))) {
            forSponsor = boleroToken.balanceOf(address(this));
            amount = forSponsor * pricePerShare;
        }

        uint256 amountForBolero = (amount * shareForBolero) / MAXIMUM_PERCENT;
        uint256 amountForArtist = amount - amountForBolero;
        return (amountForBolero, amountForArtist, forSponsor);
    }

    /*******************************************************************************
     ** @notice
     **  Allow bolero to send tokens to a list of recipients, bypassing the ICO
     **      restrictions
     ** @param recipients: List of addresses to receive the tokens
     ** @param values: amount of tokens to allocate to each recipient
     *******************************************************************************/
    function grantTokens(address[] memory recipients, uint256[] memory values)
        external
        onlyBoleroOrManagement
    {
        for (uint256 i = 0; i < recipients.length; i++)
            boleroToken.transferFromICO(
                address(this),
                recipients[i],
                values[i]
            );
    }

    /*******************************************************************************
     ** @notice
     **  While on the ICO, the want token are stored in a treasure, with a part
     **      for bolero, and another part for the artist. This function can be used
     **      to withdraw the funds.
     *******************************************************************************/
    function claimTreasure() public {
        require(boleroToken.isEmergencyPause() == false, "!emergency");
        uint256 claimableBolero = boleroTreasure;
        boleroTreasure = 0;
        require(want.transfer(BoleroABI(bolero).rewards(), claimableBolero));

        uint256 claimableArtist = artistTreasure;
        artistTreasure = 0;
        require(want.transfer(boleroArtist.artistPayment(), claimableArtist));
        if (boleroArtist.isWithPaymentSplitter()) {
            PaymentSplitterABI(boleroArtist.artistPayment()).releaseToken(
                address(want)
            );
        }
    }

    /*******************************************************************************
     ** @notice
     **  While on the initial coin offering, the price of the token is updated
     **      every week by Bolero.
     ** @param _pricePerShare: the new price
     *******************************************************************************/
    function setPricePerShare(uint256 _pricePerShare)
        public
        onlyBoleroOrManagement
    {
        _setPricePerShare(_pricePerShare);
    }

      function _setPricePerShare(uint256 _pricePerShare) internal {
        require(_pricePerShare != 0, "invalid pricePerShare");

        pricePerShare = _pricePerShare;
        emit SetPricePerShare(_pricePerShare);
    }

    /*******************************************************************************
     ** @notice Update the share distribution between Bolero and the Artist
     ** @param _shareForBolero: the new share for Bolero
     ** @param _shareForArtist: the new share for the Artist
     *******************************************************************************/
    function setShares(uint256 _shareForBolero, uint256 _shareForArtist)
        public
        onlyBoleroOrManagement
    {
        _setShares(_shareForBolero, _shareForArtist);
    }

    function _setShares(uint256 _shareForBolero, uint256 _shareForArtist)
        internal
    {
        require(
            _shareForBolero + _shareForArtist == MAXIMUM_PERCENT,
            "invalid shares"
        );
        shareForBolero = _shareForBolero;
        shareForArtist = _shareForArtist;
        emit SetShares(_shareForBolero, _shareForArtist);
    }
}
