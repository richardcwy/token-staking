// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OurStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Stakeholder {
        address addr;
        Stake[] stakes;
    }

    struct RewardPool {
        uint256 total;
        uint256 available;
        uint256 distributed;
    }

    struct RewardPlan {
        uint256 index;
        uint256 duration;
        uint256 rate;
        bool enabled;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Stake {
        uint256 index;
        uint256 amount;
        uint256 rewardPlanIndex;
        uint256 createdAt;
    }

    address private _owner;
    IERC20 public token;

    uint256 public stakeholderCount;
    mapping(address => Stakeholder) public stakeholders;

    uint256 public totalStaked;

    RewardPool public rewardPool;

    RewardPlan[] public rewardPlans;

    constructor(address _token) {
        _owner = msg.sender;
        token = IERC20(_token);
    }

    modifier onlyStakeholder() {
        require(isStakeholder(msg.sender), "OurStaking: caller is not the stakeholder");
        _;
    }

    modifier validRewardPlanIndex(uint256 _index) {
        require(_index < rewardPlans.length, "OurStaking: reward plan does not exist");
        _;
    }

    modifier validStakeIndex(address _stakeholder, uint256 _index) {
        require(_index < stakeholders[_stakeholder].stakes.length, "OurStaking: stake does not exist");
        _;
    }

    function getRewardPlans()
        external
        view
        returns (RewardPlan[] memory)
    {
        return rewardPlans;
    }

    function stakesOf(address _stakeholder)
        external
        view
        returns (Stake[] memory)
    {
        return stakeholders[_stakeholder].stakes;
    }

    function balance()
        public
        view
        returns (uint256)
    {
        return token.balanceOf(address(this));
    }

    function isStakeholder(address _stakeholder)
        public
        view
        returns (bool)
    {
        return stakeholders[_stakeholder].addr != address(0);
    }

    function createStake(uint256 _amount, uint256 _rewardPlanIndex)
        public
        nonReentrant
        validRewardPlanIndex(_rewardPlanIndex)
    {
        require(_amount > 0, "OurStaking: amount cannot be zero");
        RewardPlan memory _rewardPlan = rewardPlans[_rewardPlanIndex];
        require(_rewardPlan.enabled, "OurStaking: reward plan does not exist");
        if (!isStakeholder(msg.sender)) {
            addStakeholder(msg.sender);
        }
        Stake memory _stake = Stake({
            index: stakeholders[msg.sender].stakes.length,
            amount: _amount,
            rewardPlanIndex: _rewardPlanIndex,
            createdAt: block.timestamp
        });
        stakeholders[msg.sender].stakes.push(_stake);
        uint256 _reward = calculateReward(_stake);
        require(_reward <= rewardPool.available, "OurStaking: insufficient reward");
        totalStaked += _amount;
        rewardPool.available -= _reward;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit StakeCreated(msg.sender, _stake, _rewardPlan, _reward);
    }

    function removeStake(uint256 _stakeIndex)
        public
        nonReentrant
        onlyStakeholder
        validStakeIndex(msg.sender, _stakeIndex)
    {
        Stake memory _stake = stakeholders[msg.sender].stakes[_stakeIndex];
        uint256 _amount = _stake.amount;
        require(_amount > 0, "OurStaking: stake does not exist");
        RewardPlan memory _rewardPlan = rewardPlans[_stake.rewardPlanIndex];
        require(block.timestamp - _stake.createdAt > _rewardPlan.duration, "OurStaking: stake is still locked");
        delete stakeholders[msg.sender].stakes[_stakeIndex];
        totalStaked -= _amount;
        uint256 _reward = calculateReward(_stake);
        rewardPool.distributed += _reward;
        token.safeTransfer(msg.sender, _amount + _reward);
        emit StakeRemoved(msg.sender, _stake, _rewardPlan, _reward);
    }

    function increaseRewardPool(uint256 _amount)
        public
        nonReentrant
        onlyOwner
    {
        rewardPool.total += _amount;
        rewardPool.available += _amount;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardPoolIncreased(_amount);
    }

    function decreaseRewardPool(uint256 _amount)
        public
        nonReentrant
        onlyOwner
    {
        require(_amount <= rewardPool.available, "OurStaking: invalid amount");
        rewardPool.total -= _amount;
        rewardPool.available -= _amount;
        token.safeTransfer(msg.sender, _amount);
        emit RewardPoolDecreased(_amount);
    }

    function createRewardPlan(uint256 _duration, uint256 _rate)
        public
        onlyOwner
    {
        require(_duration > 0, "OurStaking: duration cannot be zero");
        require(_rate > 0, "OurStaking: rate cannot be zero");
        RewardPlan memory _rewardPlan = RewardPlan({
            index: rewardPlans.length,
            duration: _duration,
            rate: _rate,
            enabled: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        rewardPlans.push(_rewardPlan);
        emit RewardPlanCreated(_rewardPlan);
    }

    function enableRewardPlan(uint256 _index)
        public
        onlyOwner
        validRewardPlanIndex(_index)
    {
        rewardPlans[_index].enabled = true;
        rewardPlans[_index].updatedAt = block.timestamp;
        emit RewardPlanEnabled(rewardPlans[_index]);
    }

    function disableRewardPlan(uint256 _index)
        public
        onlyOwner
        validRewardPlanIndex(_index)
    {
        rewardPlans[_index].enabled = false;
        rewardPlans[_index].updatedAt = block.timestamp;
        emit RewardPlanDisabled(rewardPlans[_index]);
    }

    function rewardRateDecimals()
        public
        pure
        returns (uint8)
    {
        return 4;
    }

    function calculateReward(Stake memory _stake)
        internal
        view
        onlyStakeholder
        returns (uint256)
    {
        RewardPlan memory _rewardPlan = rewardPlans[_stake.rewardPlanIndex];
        return _rewardPlan.duration * _stake.amount * _rewardPlan.rate / (10 ** this.rewardRateDecimals()) / 365 days;
    }

    function addStakeholder(address _stakeholder)
        internal
    {
        stakeholders[_stakeholder].addr = _stakeholder;
        stakeholderCount++;
    }

    event StakeCreated(address indexed stakeholder, Stake stake, RewardPlan rewardPlan, uint256 reward);
    event StakeRemoved(address indexed stakeholder, Stake stake, RewardPlan rewardPlan, uint256 reward);
    event RewardPoolIncreased(uint256 amount);
    event RewardPoolDecreased(uint256 amount);
    event RewardPlanCreated(RewardPlan rewardPlan);
    event RewardPlanEnabled(RewardPlan rewardPlan);
    event RewardPlanDisabled(RewardPlan rewardPlan);
}
