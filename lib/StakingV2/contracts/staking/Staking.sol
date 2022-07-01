// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../security/BasePauseableUpgradeable.sol";
import "../interfaces/IYOPRewards.sol";
import "../interfaces/IAccessControlManager.sol";
import "../interfaces/IStaking.sol";

/// @notice This contract will stake (lock) YOP tokens for a period of time. While the tokens are locked in this contract, users will be able to claim additional YOP tokens (from the community emission as per YOP tokenomics).
///  Users can stake as many times as they want, but each stake can't be modified/extended once it is created.
///  For each stake, the user will recive an ERC1155 NFT token as the receipt. These NFT tokens can be transferred to other to still allow users to use the locked YOP tokens as a collateral.
///  When the NFT tokens are transferred, all the remaining unclaimed rewards will be transferred to the new owner as well.
contract Staking is IStaking, ERC1155Upgradeable, BasePauseableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event Staked(
    address indexed _user,
    uint256 indexed _tokenId,
    uint248 indexed _amount,
    uint8 _lockPeriod,
    uint256 _startTime
  );
  event Unstaked(
    address indexed _user,
    uint256 indexed _tokenId,
    uint248 indexed _amount,
    uint8 _lockPeriod,
    uint256 _startTime
  );

  /// @notice Emitted when the contract URI is updated
  event StakingContractURIUpdated(string _contractURI);
  /// @notice Emitted when the access control manager is updated
  event AccessControlManagerUpdated(address indexed _accessControlManager);
  /// @notice Emitted when staking limit is updated
  event StakingLimitUpdated(uint256 indexed _newLimit);

  /// @dev represent each stake
  struct Stake {
    // the duration of the stake, in number of months
    uint8 lockPeriod;
    // amount of YOP tokens to stake
    uint248 amount;
    // when the stake is started
    uint256 startTime;
    // when the last time the NFT is transferred. This is useful to help us track how long an account has hold the token
    uint256 lastTransferTime;
  }

  uint8 public constant MAX_LOCK_PERIOD = 60;
  uint256 public constant SECONDS_PER_MONTH = 2629743; // 1 month/30.44 days
  address public constant YOP_ADDRESS = 0xAE1eaAE3F627AAca434127644371b67B18444051;
  /// @notice The name of the token
  string public name;
  /// @notice The symbol of the token
  string public symbol;
  /// @notice The URL for the storefront-level metadata
  string public contractURI;
  /// @notice Used by OpenSea for admin access of the collection
  address public owner;
  // the minimum amount for staking
  uint256 public minStakeAmount;
  // the total supply of "working balance". The "working balance" of each stake is calculated as amount * lockPeriod.
  uint256 public totalWorkingSupply;
  // all the stake positions
  Stake[] public stakes;
  // the address of the YOPRewards contract
  address public yopRewards;
  // the address of the AccessControlManager contract
  address public accessControlManager;
  // stakes for each account
  mapping(address => uint256[]) internal stakesForAddress;
  // ownership of the NFTs
  mapping(uint256 => address) public owners;
  // cap for staking
  uint256 public stakingLimit;

  // solhint-disable-next-line no-empty-blocks
  constructor() {}

  /// @notice Initialize the contract.
  /// @param _governance the governance address
  /// @param _gatekeeper the gatekeeper address
  /// @param _yopRewards the address of the yop rewards contract
  /// @param _uri the base URI for the token
  function initialize(
    string memory _name,
    string memory _symbol,
    address _governance,
    address _gatekeeper,
    address _yopRewards,
    string memory _uri,
    string memory _contractURI,
    address _owner,
    address _accessControlManager
  ) external virtual initializer {
    __Staking_init(
      _name,
      _symbol,
      _governance,
      _gatekeeper,
      _yopRewards,
      _uri,
      _contractURI,
      _owner,
      _accessControlManager
    );
  }

  // solhint-disable-next-line func-name-mixedcase
  function __Staking_init(
    string memory _name,
    string memory _symbol,
    address _governance,
    address _gatekeeper,
    address _yopRewards,
    string memory _uri,
    string memory _contractURI,
    address _owner,
    address _accessControlManager
  ) internal onlyInitializing {
    __ERC1155_init(_uri);
    __BasePauseableUpgradeable_init(_governance, _gatekeeper);
    __Staking_init_unchained(_name, _symbol, _yopRewards, _contractURI, _owner, _accessControlManager);
  }

  // solhint-disable-next-line func-name-mixedcase
  function __Staking_init_unchained(
    string memory _name,
    string memory _symbol,
    address _yopRewards,
    string memory _contractURI,
    address _owner,
    address _accessControlManager
  ) internal onlyInitializing {
    require(_yopRewards != address(0), "!input");
    require(_owner != address(0), "!input");
    name = _name;
    symbol = _symbol;
    yopRewards = _yopRewards;
    owner = _owner;
    stakingLimit = type(uint256).max;
    _updateContractURI(_contractURI);
    _updateAccessControlManager(_accessControlManager);
  }

  /// @notice Set the minimum amount of tokens for staking
  /// @param _minAmount The minimum amount of tokens
  function setMinStakeAmount(uint256 _minAmount) external onlyGovernance {
    minStakeAmount = _minAmount;
  }

  /// @notice Set the limit of staking.
  /// @param _limit The limit value. It is the limit of the total working balance (combined value of number of tokens and stake duration)
  function setStakingLimit(uint256 _limit) external onlyGovernance {
    if (stakingLimit != _limit) {
      stakingLimit = _limit;
      emit StakingLimitUpdated(_limit);
    }
  }

  /// @dev Set the contractURI for store front metadata. Can only be called by governance.
  /// @param _contractURI URL of the metadata
  function setContractURI(string memory _contractURI) external onlyGovernance {
    _updateContractURI(_contractURI);
  }

  function setAccessControlManager(address _accessControlManager) external onlyGovernance {
    _updateAccessControlManager(_accessControlManager);
  }

  /// @notice Create a new staking position
  /// @param _amount The amount of YOP tokens to stake
  /// @param _lockPeriod The locking period of the stake, in months
  /// @return The id of the NFT token that is also the id of the stake
  function stake(uint248 _amount, uint8 _lockPeriod) external whenNotPaused returns (uint256) {
    return _mintStake(_amount, _lockPeriod, _msgSender());
  }

  /// @notice Unstake a single staking position that is owned by the caller after it's unlocked, and transfer the unlocked tokens to the _to address
  /// @param _stakeId The id of the staking NFT token, and owned by the caller
  function unstakeSingle(uint256 _stakeId, address _to) external whenNotPaused {
    _burnSingle(_stakeId, _to);
  }

  /// @notice Unstake all the unlocked stakes the caller currently has and transfer all the tokens to _to address in a single transfer.
  ///  This will be more gas efficient if the caller has multiple stakes that are unlocked.
  /// @param _to the address that will receive the tokens
  function unstakeAll(address _to) external whenNotPaused {
    _burnAll(_to);
  }

  /// @notice Lists the is of stakes for a user
  /// @param _user The user address
  /// @return the ids of stakes
  function stakesFor(address _user) external view returns (uint256[] memory) {
    return stakesForAddress[_user];
  }

  /// @notice Check the working balance of an user address.
  /// @param _user The user address
  /// @return The value of working balance
  function workingBalanceOf(address _user) external view returns (uint256) {
    uint256 balance = 0;
    uint256[] memory stakeIds = stakesForAddress[_user];
    for (uint256 i = 0; i < stakeIds.length; i++) {
      balance += _workingBalanceOfStake(stakes[stakeIds[i]]);
    }
    return balance;
  }

  /// @notice Get the working balance for the stake with the given stake id.
  /// @param _stakeId The id of the stake
  /// @return The working balance, calculated as stake.amount * stake.lockPeriod
  function workingBalanceOfStake(uint256 _stakeId) external view returns (uint256) {
    if (_stakeId < stakes.length) {
      Stake memory s = stakes[_stakeId];
      return _workingBalanceOfStake(s);
    }
    return 0;
  }

  function _workingBalanceOfStake(Stake memory _stake) internal pure returns (uint256) {
    return _stake.amount * _stake.lockPeriod;
  }

  function _isUnlocked(Stake memory _stake) internal view returns (bool) {
    return _getBlockTimestamp() > (_stake.startTime + _stake.lockPeriod * SECONDS_PER_MONTH);
  }

  function _getUnlockedStakeIds(uint256[] memory _stakeIds) internal view returns (uint256[] memory) {
    // solidity doesn't allow changing the size of memory arrays dynamically, so have to use this function to build the array that only contains stake ids that are unlocked
    uint256[] memory temp = new uint256[](_stakeIds.length);
    uint256 counter;
    for (uint256 i = 0; i < _stakeIds.length; i++) {
      Stake memory s = stakes[_stakeIds[i]];
      // find all the unlocked stakes first and store them in an array
      if (_isUnlocked(s)) {
        temp[counter] = _stakeIds[i];
        counter++;
      }
    }
    // copy the array to change the size
    uint256[] memory unlocked;
    if (counter > 0) {
      unlocked = new uint256[](counter);
      for (uint256 j = 0; j < counter; j++) {
        unlocked[j] = temp[j];
      }
    }
    return unlocked;
  }

  /// @dev This function is invoked by the ERC1155 implementation. It will be called everytime when tokens are minted, transferred and burned.
  ///  We add implementation for this function to perform the common bookkeeping tasks, like update the working balance, update ownership mapping etc.
  function _beforeTokenTransfer(
    address,
    address _from,
    address _to,
    uint256[] memory _ids,
    uint256[] memory,
    bytes memory
  ) internal override {
    for (uint256 i = 0; i < _ids.length; i++) {
      uint256 tokenId = _ids[i];
      Stake storage s = stakes[tokenId];
      s.lastTransferTime = _getBlockTimestamp();
      uint256 balance = _workingBalanceOfStake(s);
      if (_from != address(0)) {
        totalWorkingSupply -= balance;
        _removeValue(stakesForAddress[_from], tokenId);
        owners[tokenId] = address(0);
      }
      if (_to != address(0)) {
        totalWorkingSupply += balance;
        stakesForAddress[_to].push(tokenId);
        owners[tokenId] = _to;
      } else {
        // this is a burn, reset the fields of the stake record
        delete stakes[tokenId];
      }
    }
  }

  /// @dev For testing
  function _getBlockTimestamp() internal view virtual returns (uint256) {
    // solhint-disable-next-line not-rely-on-time
    return block.timestamp;
  }

  /// @dev For testing
  function _getYOPAddress() internal view virtual returns (address) {
    return YOP_ADDRESS;
  }

  function _removeValue(uint256[] storage _values, uint256 _val) internal {
    uint256 i;
    for (i = 0; i < _values.length; i++) {
      if (_values[i] == _val) {
        break;
      }
    }
    for (; i < _values.length - 1; i++) {
      _values[i] = _values[i + 1];
    }
    _values.pop();
  }

  function _updateAccessControlManager(address _accessControlManager) internal {
    // no check on the parameter as it can be address(0)
    if (accessControlManager != _accessControlManager) {
      accessControlManager = _accessControlManager;
      emit AccessControlManagerUpdated(_accessControlManager);
    }
  }

  function _updateContractURI(string memory _contractURI) internal {
    contractURI = _contractURI;
    emit StakingContractURIUpdated(_contractURI);
  }

  function _mintStake(
    uint248 _amount,
    uint8 _lockPeriod,
    address _to
  ) internal returns (uint256) {
    require(_amount > minStakeAmount, "!amount");
    require(_lockPeriod > 0 && _lockPeriod <= MAX_LOCK_PERIOD, "!lockPeriod");
    require(IERC20Upgradeable(_getYOPAddress()).balanceOf(_msgSender()) >= _amount, "!balance");
    require((totalWorkingSupply + _amount * _lockPeriod) <= stakingLimit, "limit reached");
    if (accessControlManager != address(0)) {
      require(IAccessControlManager(accessControlManager).hasAccess(_to, address(this)), "!access");
    }
    // issue token id
    uint256 tokenId = stakes.length;
    // calculate the rewards for the token.
    // This only needs to be called when NFT tokens are minted/burne. It doesn't need to be called again when NFTs are transferred as the balance of the token and the totalBalance are not changed when tokens are transferred
    // This needs to be called before the stakes array is updated as otherwise the workingBalanceOfStake will return a value.
    IYOPRewards(yopRewards).calculateStakingRewards(tokenId);
    // record the stake
    Stake memory s = Stake({
      lockPeriod: _lockPeriod,
      amount: _amount,
      startTime: _getBlockTimestamp(),
      lastTransferTime: _getBlockTimestamp()
    });
    stakes.push(s);
    // transfer the the tokens to this contract and mint an NFT token
    IERC20Upgradeable(_getYOPAddress()).safeTransferFrom(_msgSender(), address(this), _amount);
    bytes memory data;
    _mint(_to, tokenId, 1, data);
    emit Staked(_to, tokenId, _amount, _lockPeriod, _getBlockTimestamp());
    return tokenId;
  }

  function _burnSingle(uint256 _stakeId, address _to) internal {
    require(_to != address(0), "!input");
    require(balanceOf(_msgSender(), _stakeId) > 0, "!stake");
    Stake memory s = stakes[_stakeId];
    uint256 startTime = s.startTime;
    uint248 amount = s.amount;
    uint8 lockPeriod = s.lockPeriod;
    require(_isUnlocked(s), "locked");
    // This only needs to be called when NFT tokens are minted/burne. It doesn't need to be called again when NFTs are transferred as the balance of the token and the totalBalance are not changed when tokens are transferred
    uint256[] memory stakeIds = new uint256[](1);
    stakeIds[0] = _stakeId;
    (uint256 rewardsAmount, ) = IYOPRewardsV2(yopRewards).claimRewardsForStakes(stakeIds);
    // burn the NFT
    _burn(_msgSender(), _stakeId, 1);
    // transfer the tokens to _to
    IERC20Upgradeable(_getYOPAddress()).safeTransfer(_to, amount + rewardsAmount);
    emit Unstaked(_msgSender(), _stakeId, amount, lockPeriod, startTime);
  }

  function _burnAll(address _to) internal {
    require(_to != address(0), "!input");
    uint256[] memory stakeIds = stakesForAddress[_msgSender()];
    uint256[] memory unlockedIds = _getUnlockedStakeIds(stakeIds);
    require(unlockedIds.length > 0, "!unlocked");
    (uint256 toTransfer, ) = IYOPRewardsV2(yopRewards).claimRewardsForStakes(unlockedIds);
    uint256[] memory amounts = new uint256[](unlockedIds.length);
    for (uint256 i = 0; i < unlockedIds.length; i++) {
      amounts[i] = 1;
      Stake memory s = stakes[unlockedIds[i]];
      uint256 startTime = s.startTime;
      uint248 amount = s.amount;
      uint8 lockPeriod = s.lockPeriod;
      toTransfer += amount;
      emit Unstaked(_msgSender(), unlockedIds[i], amount, lockPeriod, startTime);
    }
    // burn the NFTs
    _burnBatch(_msgSender(), unlockedIds, amounts);
    // transfer the tokens to _to
    IERC20Upgradeable(_getYOPAddress()).safeTransfer(_to, toTransfer);
  }
}
