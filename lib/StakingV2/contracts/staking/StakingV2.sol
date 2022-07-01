// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./Staking.sol";
import "../interfaces/IVault.sol";

/// @dev Add a new stake function that will update the user's boost balance in selected vaults immediately after staking
contract StakingV2 is IStakingV2, Staking, ReentrancyGuardUpgradeable {
  using ERC165CheckerUpgradeable for address;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event StakeExtended(uint256 indexed _tokenId, uint248 indexed _newAmount, uint8 _newlockPeriod, address[] _vaults);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

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
  ) external virtual override initializer {
    __ReentrancyGuard_init();
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

  /// @notice Return the total number of stakes created so far
  function totalSupply() external view returns (uint256) {
    return stakes.length;
  }

  /// @notice Same as `stake(uint248,uint8)`, but will take an array of vault addresses as extra parameter.
  ///  If the vault addresses are provided, the user's boosted balance in these vaults will be updated immediately after staking to take into account their latest staking positions.
  /// @param _amount The amount of YOP tokens to stake
  /// @param _lockPeriod The locking period of the stake, in months
  /// @param _vaultsToBoost The vaults that the user's boosted balance should be updated after staking
  /// @return The id of the NFT token that is also the id of the stake
  function stakeAndBoost(
    uint248 _amount,
    uint8 _lockPeriod,
    address[] calldata _vaultsToBoost
  ) external nonReentrant returns (uint256) {
    _notPaused();
    uint256 tokenId = _mintStake(_amount, _lockPeriod, _msgSender());
    _updateVaults(_vaultsToBoost, _msgSender());
    return tokenId;
  }

  /// @notice Stake the YOP tokens on behalf of another user.
  /// @param _amount The amount of YOP tokens to stake
  /// @param _lockPeriod The locking period of the stake, in months
  /// @param _to The user to send the NFT to
  /// @return The id of the NFT token that is also the id of the stake
  function stakeForUser(
    uint248 _amount,
    uint8 _lockPeriod,
    address _to
  ) external returns (uint256) {
    _notPaused();
    return _mintStake(_amount, _lockPeriod, _to);
  }

  /// @notice Stake the YOP tokens on behalf of another user and boost the user's balance in the given vaults
  /// @param _amount The amount of YOP tokens to stake
  /// @param _lockPeriod The locking period of the stake, in months
  /// @param _to The user to send the NFT to
  /// @param _vaultsToBoost The vaults that the user's boosted balance should be updated after staking
  /// @return The id of the NFT token that is also the id of the stake
  function stakeAndBoostForUser(
    uint248 _amount,
    uint8 _lockPeriod,
    address _to,
    address[] calldata _vaultsToBoost
  ) external nonReentrant returns (uint256) {
    _notPaused();
    uint256 tokenId = _mintStake(_amount, _lockPeriod, _to);
    _updateVaults(_vaultsToBoost, _to);
    return tokenId;
  }

  /// @notice Exit a single unlocked staking position, claim remaining rewards associated with the stake, and adjust the boost values in vaults
  /// @param _stakeId The id of the unlocked staking positon
  /// @param _to The recipient address that will receive the YOP tokens
  /// @param _vaultsToBoost The list of vaults that will have the boost updated
  function unstakeSingleAndBoost(
    uint256 _stakeId,
    address _to,
    address[] calldata _vaultsToBoost
  ) external nonReentrant {
    _notPaused();
    _burnSingle(_stakeId, _to);
    _updateVaults(_vaultsToBoost, _msgSender());
  }

  /// @notice Exit all unlocked staking position, claim all remaining rewards associated with the stakes, and adjust the boost values in vaults
  /// @param _to The recipient address that will receive the YOP tokens
  /// @param _vaultsToBoost The list of vaults that will have the boost updated
  function unstakeAllAndBoost(address _to, address[] calldata _vaultsToBoost) external nonReentrant {
    _notPaused();
    _burnAll(_to);
    _updateVaults(_vaultsToBoost, _msgSender());
  }

  /// @notice Increase the staking amount or lock period for a single stake position. Update the boosted balance in the list of vaults.
  /// @param _stakeId The id of the stake
  /// @param _additionalDuration The additional lockup months to add to the stake. New lockup months can not exceed maximum value.
  /// @param _additionalAmount Additional YOP amounts to add to the stake.
  /// @param _vaultsToUpdate The list of vaults that will have the boost updated for the owner of the stake
  function extendStake(
    uint256 _stakeId,
    uint8 _additionalDuration,
    uint248 _additionalAmount,
    address[] calldata _vaultsToUpdate
  ) external nonReentrant {
    _notPaused();
    require(_additionalAmount > 0 || _additionalDuration > 0, "!parameters");

    Stake storage stake = stakes[_stakeId];
    require(owners[_stakeId] == _msgSender(), "!owner");

    uint8 newLockPeriod = stake.lockPeriod;
    if (_additionalDuration > 0) {
      newLockPeriod = stake.lockPeriod + _additionalDuration;
      require(newLockPeriod <= MAX_LOCK_PERIOD, "!duration");
    }

    uint248 newAmount = stake.amount;
    if (_additionalAmount > 0) {
      require(IERC20Upgradeable(_getYOPAddress()).balanceOf(_msgSender()) >= _additionalAmount, "!balance");
      newAmount = stake.amount + _additionalAmount;
      require(newAmount >= minStakeAmount, "!amount");
    }

    uint256 newTotalWorkingSupply = (totalWorkingSupply +
      (newAmount * newLockPeriod - stake.amount * stake.lockPeriod));

    require(newTotalWorkingSupply <= stakingLimit, "limit");

    IYOPRewards(yopRewards).calculateStakingRewards(_stakeId);

    if (_additionalDuration > 0) {
      stake.lockPeriod = newLockPeriod;
    }
    if (_additionalAmount > 0) {
      IERC20Upgradeable(_getYOPAddress()).safeTransferFrom(_msgSender(), address(this), _additionalAmount);
      stake.amount = newAmount;
    }
    totalWorkingSupply = newTotalWorkingSupply;
    _updateVaults(_vaultsToUpdate, _msgSender());
    emit StakeExtended(_stakeId, newAmount, newLockPeriod, _vaultsToUpdate);
  }

  /// @notice Claim the rewards for all the given stakes, and extend each stake by the amount of rewards collected.
  /// @dev For each stake, this will basically claim the rewards for that stake, and add the rewards to the amount of that stake. No changes to the stake duration.
  ///    This is built with automation in mind so that we can build an auto-compounding feature for users if we want. However, users can call this to claim & topup their existing stakes too.
  /// @param _stakeIds The ids of the stakes that will be compounded
  function compoundForStaking(uint256[] calldata _stakeIds) external {
    _notPaused();
    uint256 totalIncreasedSupply = _compoundForStakes(_stakeIds);
    totalWorkingSupply += totalIncreasedSupply;
  }

  /// @notice Claim vault rewards for each user and top up a stake of that user. No changes to the duration of the stake.
  /// @dev This is built mainly for automation.
  /// @param _users List of user address to claim vault rewards from.
  /// @param _topupStakes The list of stakes to top up with the vault rewards. Each stake in the list should be owned by the address in the corresponding position in the `_users` list.
  ///   E.g. `_users[0]` should own `_topupStakes[0]`, `_users[1]` should own `_topupStakes[1]` and so on.
  function compoundWithVaultRewards(address[] calldata _users, uint256[] calldata _topupStakes) external {
    _notPaused();
    uint256 totalIncreasedSupply = _compoundWithVaultRewards(_users, _topupStakes);
    totalWorkingSupply += totalIncreasedSupply;
  }

  /// @notice Compound staking & vault rewards for the user in a single transaction, in a gas efficient way.
  ///   Staking rewards will be claimed and added to each stake respectively.
  ///   Vault rewards will be claimed and added to the given stake.
  /// @dev This is mainly to be called by the user, or a smart contract that will call this on a user's behalf.
  /// @param _user The user address
  /// @param _topupStakeId The stake id to add the vault rewards
  function compoundForUser(address _user, uint256 _topupStakeId) external {
    _notPaused();
    require(owners[_topupStakeId] == _user, "!owner");
    uint256[] memory stakeIds = stakesForAddress[_user];
    uint256 totalIncreasedSupply = _compoundForStakes(stakeIds);
    address[] memory users = new address[](1);
    uint256[] memory topupStakes = new uint256[](1);
    users[0] = _user;
    topupStakes[0] = _topupStakeId;
    totalIncreasedSupply += _compoundWithVaultRewards(users, topupStakes);
    totalWorkingSupply += totalIncreasedSupply;
  }

  function _updateVaults(address[] calldata _vaultsToBoost, address _user) internal {
    for (uint256 i = 0; i < _vaultsToBoost.length; i++) {
      require(_vaultsToBoost[i].supportsInterface(type(IVault).interfaceId), "!vault interface");
      if (IVault(_vaultsToBoost[i]).balanceOf(_user) > 0) {
        address[] memory users = new address[](1);
        users[0] = _user;
        IBoostedVault(_vaultsToBoost[i]).updateBoostedBalancesForUsers(users);
      }
    }
  }

  function _compoundForStakes(uint256[] memory _stakeIds) internal returns (uint256) {
    (, uint256[] memory rewardsAmount) = IYOPRewardsV2(yopRewards).claimRewardsForStakes(_stakeIds);
    uint256 totalIncreasedSupply;
    for (uint256 i = 0; i < _stakeIds.length; i++) {
      uint248 newAmount = uint248(stakes[_stakeIds[i]].amount + rewardsAmount[i]);
      stakes[_stakeIds[i]].amount = newAmount;
      totalIncreasedSupply += rewardsAmount[i] * stakes[_stakeIds[i]].lockPeriod;
      address[] memory vaults;
      emit StakeExtended(_stakeIds[i], newAmount, stakes[_stakeIds[i]].lockPeriod, vaults);
    }
    return totalIncreasedSupply;
  }

  function _compoundWithVaultRewards(address[] memory _users, uint256[] memory _topupStakes)
    internal
    returns (uint256)
  {
    (, uint256[] memory rewardsAmount) = IYOPRewardsV2(yopRewards).claimVaultRewardsForUsers(_users);
    uint256 totalIncreasedSupply;
    for (uint256 i = 0; i < _topupStakes.length; i++) {
      uint256 stakeId = _topupStakes[i];
      uint248 newAmount = uint248(stakes[stakeId].amount + rewardsAmount[i]);
      require(owners[stakeId] == _users[i], "!owner");
      stakes[stakeId].amount = newAmount;
      totalIncreasedSupply += rewardsAmount[i] * stakes[stakeId].lockPeriod;
      address[] memory vaults;
      emit StakeExtended(stakeId, newAmount, stakes[stakeId].lockPeriod, vaults);
    }
    return totalIncreasedSupply;
  }

  function _notPaused() internal view {
    require(!paused(), "Pausable: paused");
  }
}
