//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IChainlink.sol";
import "./interfaces/IFryerConfig.sol";
import "./interfaces/IVaultAdapter.sol";
import "./interfaces/IOven.sol";
import "./interfaces/IMintableERC20.sol";
import "./interfaces/IDetailedERC20.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "./interfaces/IERC3156FlashBorrower.sol";
import "./libraries/Upgradable.sol";
import "./libraries/FixedPointMath.sol";
import "./libraries/Vault.sol";
import "./libraries/CDP.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/ConfigNames.sol";
import "./libraries/Convert.sol";
import "./libraries/NoDelegateCall.sol";

contract Fryer is
    ReentrancyGuard,
    UpgradableProduct,
    IERC3156FlashLender,
    Convert,
    NoDelegateCall
{
    using CDP for CDP.Data;
    using FixedPointMath for FixedPointMath.uq192x64;
    using Vault for Vault.Data;
    using Vault for Vault.List;
    using TransferHelper for address;
    using SafeMath for uint256;
    using Address for address;

    event OvenUpdated(address indexed newOven);
    event ConfigUpdated(address indexed newConfig);
    event RewardsUpdated(address indexed reward);
    event EmergencyExitUpdated(bool indexed emergencyExit);
    event ActiveVaultUpdated(address indexed adapter);
    event FundsHarvested(
        uint256 indexed harvestedAmount,
        uint256 indexed decreasedValue
    );
    event FundsFlushed(uint256 indexed depositedAmount);
    event TokensDeposited(address indexed user, uint256 indexed amount);
    event TokensWithdrawn(
        address indexed user,
        uint256 indexed amount,
        uint256 withdrawnAmount,
        uint256 decreasedValue
    );
    event TokensRepaid(
        address indexed user,
        uint256 indexed parentAmount,
        uint256 indexed childAmount
    );
    event TokensLiquidated(
        address indexed user,
        uint256 indexed amount,
        uint256 withdrawnAmount,
        uint256 decreasedValue
    );
    event FundsRecalled(
        uint256 indexed vaultId,
        uint256 withdrawnAmount,
        uint256 decreasedValue
    );
    event UseFlashloan(
        address indexed user,
        address token,
        uint256 amount,
        uint256 fee
    );

    bytes32 public constant FLASH_CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    // DAI/USDT/ALUSD
    address public token;

    // FiresToken
    address public friesToken;

    address public oven;

    address public rewards;

    uint256 public totalDeposited;

    uint256 public flushActivator;

    bool public initialized;

    bool public emergencyExit;

    CDP.Context private _ctx;

    mapping(address => CDP.Data) private _cdps;

    Vault.List private _vaults;

    address public _linkGasOracle;

    uint256 public pegMinimum;

    IFryerConfig public fryerConfig;

    constructor(
        address _token,
        address _friesToken,
        address _fryerConfig
    ) public {
        token = _token;
        friesToken = _friesToken;
        flushActivator = 100000 * 10**uint256(IDetailedERC20(token).decimals());
        fryerConfig = IFryerConfig(_fryerConfig);
        _ctx.fryerConfig = fryerConfig;
        _ctx.accumulatedYieldWeight = FixedPointMath.uq192x64(0);
    }

    modifier expectInitialized() {
        require(initialized, "not initialized.");
        _;
    }

    function setOven(address _oven) external requireImpl {
        require(
            _oven != fryerConfig.ZERO_ADDRESS(),
            "oven address cannot be 0x0."
        );
        oven = _oven;
        emit OvenUpdated(_oven);
    }

    function setConfig(address _config) external requireImpl {
        require(
            _config != fryerConfig.ZERO_ADDRESS(),
            "config address cannot be 0x0."
        );
        fryerConfig = IFryerConfig(_config);
        _ctx.fryerConfig = fryerConfig;
        emit ConfigUpdated(_config);
    }

    function setFlushActivator(uint256 _flushActivator) external requireImpl {
        flushActivator = _flushActivator;
    }

    function setRewards(address _rewards) external requireImpl {
        require(
            _rewards != fryerConfig.ZERO_ADDRESS(),
            "rewards address cannot be 0x0."
        );
        rewards = _rewards;
        emit RewardsUpdated(_rewards);
    }

    function setOracleAddress(address Oracle, uint256 peg)
        external
        requireImpl
    {
        _linkGasOracle = Oracle;
        pegMinimum = peg;
    }

    function setEmergencyExit(bool _emergencyExit) external requireImpl {
        emergencyExit = _emergencyExit;

        emit EmergencyExitUpdated(_emergencyExit);
    }

    function collateralizationLimit()
        external
        view
        returns (FixedPointMath.uq192x64 memory)
    {
        return CDP.collateralizationLimit(_ctx);
    }

    function initialize(address _adapter) external requireImpl {
        require(!initialized, "already initialized");
        require(
            oven != fryerConfig.ZERO_ADDRESS(),
            "cannot initialize oven address to 0x0"
        );
        require(
            rewards != fryerConfig.ZERO_ADDRESS(),
            "cannot initialize rewards address to 0x0"
        );
        _updateActiveVault(_adapter);
        initialized = true;
    }

    function migrate(address _adapter) external expectInitialized requireImpl {
        _updateActiveVault(_adapter);
    }

    function _updateActiveVault(address _adapter) internal {
        require(
            _adapter != fryerConfig.ZERO_ADDRESS(),
            "active vault address cannot be 0x0."
        );
        IVaultAdapter adapter = IVaultAdapter(_adapter);
        require(adapter.token() == token, "token mismatch.");
        _vaults.push(Vault.Data({adapter: adapter, totalDeposited: 0}));
        emit ActiveVaultUpdated(_adapter);
    }

    function harvest(uint256 _vaultId)
        external
        expectInitialized
        returns (uint256, uint256)
    {
        Vault.Data storage _vault = _vaults.get(_vaultId);

        (uint256 _harvestedAmount, uint256 _decreasedValue) =
            _vault.harvest(address(this));

        _incomeDistribution(_harvestedAmount);

        emit FundsHarvested(_harvestedAmount, _decreasedValue);

        return (_harvestedAmount, _decreasedValue);
    }

    function _incomeDistribution(uint256 amount) internal {
        if (amount > 0) {
            uint256 feeRate = fryerConfig.getConfigValue(ConfigNames.FRYER_HARVEST_FEE);
            uint256 _feeAmount =  amount.mul(feeRate).div(fryerConfig.PERCENT_DENOMINATOR());
            uint256 _distributeAmount = amount.sub(_feeAmount);

            if (totalDeposited > 0) {
                FixedPointMath.uq192x64 memory _weight =
                    FixedPointMath.fromU256(_distributeAmount).div(
                        totalDeposited
                    );
                _ctx.accumulatedYieldWeight = _ctx.accumulatedYieldWeight.add(
                    _weight
                );
            }

            if (_feeAmount > 0) {
                token.safeTransfer(rewards, _feeAmount);
            }

            if (_distributeAmount > 0) {
                _distributeToOven(_distributeAmount);
            }
        }
    }

    function recall(uint256 _vaultId, uint256 _amount)
        external
        nonReentrant
        expectInitialized
        returns (uint256, uint256)
    {
        return _recallFunds(_vaultId, _amount);
    }

    function recallAll(uint256 _vaultId)
        external
        nonReentrant
        expectInitialized
        returns (uint256, uint256)
    {
        Vault.Data storage _vault = _vaults.get(_vaultId);
        return _recallFunds(_vaultId, _vault.totalDeposited);
    }

    function flush() external nonReentrant expectInitialized returns (uint256) {
        require(!emergencyExit, "emergency pause enabled");

        return flushActiveVault();
    }

    function flushActiveVault() internal returns (uint256) {
        Vault.Data storage _activeVault = _vaults.last();
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 ratio = fryerConfig.getConfigValue(ConfigNames.FRYER_VAULT_PERCENTAGE);
        uint256 pendingTotal =
            balance.add(_activeVault.totalDeposited).mul(ratio)
                .div(fryerConfig.PERCENT_DENOMINATOR());
        if (pendingTotal > _activeVault.totalDeposited) {
            uint256 _depositedAmount =
                _activeVault.deposit(
                    pendingTotal.sub(_activeVault.totalDeposited)
                );
            emit FundsFlushed(_depositedAmount);
            return _depositedAmount;
        } else {
            return 0;
        }
    }

    function deposit(uint256 _amount)
        external
        nonReentrant
        noDelegateCall
        noContractAllowed
        expectInitialized
    {
        require(!emergencyExit, "emergency pause enabled");

        CDP.Data storage _cdp = _cdps[msg.sender];
        _cdp.update(_ctx);

        token.safeTransferFrom(msg.sender, address(this), _amount);

        totalDeposited = totalDeposited.add(_amount);

        _cdp.totalDeposited = _cdp.totalDeposited.add(_amount);
        _cdp.lastDeposit = block.number;

        if (_amount >= flushActivator) {
            flushActiveVault();
        }

        emit TokensDeposited(msg.sender, _amount);
    }

    function withdraw(uint256 _amount)
        external
        nonReentrant
        noDelegateCall
        noContractAllowed
        expectInitialized
        returns (uint256, uint256)
    {
        CDP.Data storage _cdp = _cdps[msg.sender];
        require(block.number > _cdp.lastDeposit, "");

        _cdp.update(_ctx);

        (uint256 _withdrawnAmount, uint256 _decreasedValue) =
            _withdrawFundsTo(msg.sender, _amount);

        _cdp.totalDeposited = _cdp.totalDeposited.sub(
            _decreasedValue,
            "Exceeds withdrawable amount"
        );
        _cdp.checkHealth(
            _ctx,
            "Action blocked: unhealthy collateralization ratio"
        );
        if (_amount >= flushActivator) {
            flushActiveVault();
        }
        emit TokensWithdrawn(
            msg.sender,
            _amount,
            _withdrawnAmount,
            _decreasedValue
        );

        return (_withdrawnAmount, _decreasedValue);
    }

    function repay(uint256 _parentAmount, uint256 _childAmount)
        external
        nonReentrant
        noDelegateCall
        noContractAllowed
        onLinkCheck
        expectInitialized
    {
        CDP.Data storage _cdp = _cdps[msg.sender];
        _cdp.update(_ctx);

        if (_parentAmount > 0) {
            token.safeTransferFrom(msg.sender, address(this), _parentAmount);
            _distributeToOven(_parentAmount);
        }

        uint256 childAmount_ =
            convertTokenAmount(friesToken, token, _childAmount);
        // friesUsd convert USDT/DAI/USDC > 0
        if (childAmount_ > 0) {
            IMintableERC20(friesToken).burnFrom(msg.sender, _childAmount);
            IMintableERC20(friesToken).lowerHasMinted(_childAmount);
        } else {
            _childAmount = 0;
        }

        uint256 _totalAmount = _parentAmount.add(childAmount_);
        _cdp.totalDebt = _cdp.totalDebt.sub(_totalAmount);

        emit TokensRepaid(msg.sender, _parentAmount, _childAmount);
    }

    function liquidate(uint256 _amount)
        external
        nonReentrant
        noDelegateCall
        noContractAllowed
        onLinkCheck
        expectInitialized
        returns (uint256, uint256)
    {
        CDP.Data storage _cdp = _cdps[msg.sender];
        _cdp.update(_ctx);

        if (_amount > _cdp.totalDebt) {
            _amount = _cdp.totalDebt;
        }
        (uint256 _withdrawnAmount, uint256 _decreasedValue) =
            _withdrawFundsTo(address(this), _amount);
        _distributeToOven(_withdrawnAmount);

        _cdp.totalDeposited = _cdp.totalDeposited.sub(_decreasedValue);
        _cdp.totalDebt = _cdp.totalDebt.sub(_withdrawnAmount);
        emit TokensLiquidated(
            msg.sender,
            _amount,
            _withdrawnAmount,
            _decreasedValue
        );

        return (_withdrawnAmount, _decreasedValue);
    }

    function borrow(uint256 _amount)
        external
        nonReentrant
        noDelegateCall
        noContractAllowed
        onLinkCheck
        expectInitialized
    {
        CDP.Data storage _cdp = _cdps[msg.sender];
        _cdp.update(_ctx);

        uint256 _totalCredit = _cdp.totalCredit;

        if (_totalCredit < _amount) {
            uint256 _remainingAmount = _amount.sub(_totalCredit);
            _cdp.totalDebt = _cdp.totalDebt.add(_remainingAmount);
            _cdp.totalCredit = 0;
            _cdp.checkHealth(_ctx, "Loan-to-value ratio breached");
        } else {
            _cdp.totalCredit = _totalCredit.sub(_amount);
        }
        uint256 mint = convertTokenAmount(token, friesToken, _amount);
        IMintableERC20(friesToken).mint(msg.sender, mint);
        if (_amount >= flushActivator) {
            flushActiveVault();
        }
    }

    function vaultCount() external view returns (uint256) {
        return _vaults.length();
    }

    function getVaultAdapter(uint256 _vaultId)
        external
        view
        returns (IVaultAdapter)
    {
        Vault.Data storage _vault = _vaults.get(_vaultId);
        return _vault.adapter;
    }

    function getVaultTotalDeposited(uint256 _vaultId)
        external
        view
        returns (uint256)
    {
        Vault.Data storage _vault = _vaults.get(_vaultId);
        return _vault.totalDeposited;
    }

    function getCdpTotalDeposited(address _account)
        external
        view
        returns (uint256)
    {
        CDP.Data storage _cdp = _cdps[_account];
        return _cdp.totalDeposited;
    }

    function getCdpTotalDebt(address _account) external view returns (uint256) {
        CDP.Data storage _cdp = _cdps[_account];
        return _cdp.getUpdatedTotalDebt(_ctx);
    }

    function getCdpTotalCredit(address _account)
        external
        view
        returns (uint256)
    {
        CDP.Data storage _cdp = _cdps[_account];
        return _cdp.getUpdatedTotalCredit(_ctx);
    }

    function getCdpLastDeposit(address _account)
        external
        view
        returns (uint256)
    {
        CDP.Data storage _cdp = _cdps[_account];
        return _cdp.lastDeposit;
    }

    function _distributeToOven(uint256 amount) internal {
        token.safeApprove(oven, amount);
        IOven(oven).distribute(address(this), amount);
        uint256 mintAmount = convertTokenAmount(token, friesToken, amount);
        IMintableERC20(friesToken).lowerHasMinted(mintAmount);
    }

    modifier onLinkCheck() {
        if (pegMinimum > 0) {
            uint256 oracleAnswer =
                uint256(IChainlink(_linkGasOracle).latestAnswer());
            require(oracleAnswer > pegMinimum, "off peg limitation");
        }
        _;
    }

    modifier noContractAllowed() {
        require(
            !address(msg.sender).isContract() && msg.sender == tx.origin,
            "Sorry we do not accept contract!"
        );
        _;
    }

    function _recallFunds(uint256 _vaultId, uint256 _amount)
        internal
        returns (uint256, uint256)
    {
        require(
            emergencyExit ||
                msg.sender == impl ||
                _vaultId != _vaults.lastIndex(),
            "not an emergency, not governance, and user does not have permission to recall funds from active vault"
        );

        Vault.Data storage _vault = _vaults.get(_vaultId);
        (uint256 _withdrawnAmount, uint256 _decreasedValue) =
            _vault.withdraw(address(this), _amount);

        emit FundsRecalled(_vaultId, _withdrawnAmount, _decreasedValue);

        return (_withdrawnAmount, _decreasedValue);
    }

    function _withdrawFundsTo(address _recipient, uint256 _amount)
        internal
        returns (uint256, uint256)
    {
        uint256 _bufferedAmount =
            Math.min(_amount, IERC20(token).balanceOf(address(this)));

        if (_recipient != address(this)) {
            token.safeTransfer(_recipient, _bufferedAmount);
        }

        uint256 _totalWithdrawn = _bufferedAmount;
        uint256 _totalDecreasedValue = _bufferedAmount;

        uint256 _remainingAmount = _amount.sub(_bufferedAmount);
        if (_remainingAmount > 0) {
            Vault.Data storage _activeVault = _vaults.last();
            (uint256 _withdrawAmount, uint256 _decreasedValue) =
                _activeVault.withdraw(_recipient, _remainingAmount);

            _totalWithdrawn = _totalWithdrawn.add(_withdrawAmount);
            _totalDecreasedValue = _totalDecreasedValue.add(_decreasedValue);
        }

        totalDeposited = totalDeposited.sub(_totalDecreasedValue);

        return (_totalWithdrawn, _totalDecreasedValue);
    }

    // flash

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token_,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(token == token_, "FlashLender: Unsupported currency");
        uint256 _fee = _flashFee(amount);
        token.safeTransfer(address(receiver), amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, _fee, data) ==
                FLASH_CALLBACK_SUCCESS,
            "FlashLender: Callback failed"
        );
        token.safeTransferFrom(
            address(receiver),
            address(this),
            amount.add(_fee)
        );

        _incomeDistribution(_fee);
        emit UseFlashloan(tx.origin, token, amount, _fee);
        return true;
    }

    function flashFee(address token_, uint256 amount)
        external
        view
        override
        returns (uint256)
    {
        require(token == token_, "FlashLender: Unsupported currency");
        return _flashFee(amount);
    }

    function _flashFee(uint256 amount) internal view returns (uint256) {
        uint256 prop =
            fryerConfig.getConfigValue(ConfigNames.FRYER_FLASH_FEE_PROPORTION);
        uint256 PERCENT_DENOMINATOR = fryerConfig.PERCENT_DENOMINATOR();
        return amount.mul(prop).div(PERCENT_DENOMINATOR);
    }

    /**
     * @dev The amount of currency available to be lended.
     * @param token_ The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token_)
        external
        view
        override
        returns (uint256)
    {
        if (token == token_) {
            return IERC20(token).balanceOf(address(this));
        } else {
            return 0;
        }
    }
}
