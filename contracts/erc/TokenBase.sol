// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {WadRayMath} from '../libraries/WadRayMath.sol';

import {IAvaToken} from '../interfaces/IAvaToken.sol';
// import "hardhat/console.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
/* contract ERC20 is Context, IERC20, IERC20Metadata { */
abstract contract TokenBase is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    uint256 private _totalFloat;

    string private _name;
    string private _symbol;

    mapping(address => bool) private _dividendsBlacklist;
    mapping(address => bool) private _balanceBlacklistedWith;

    function addDividendsBlacklist(address user) internal virtual {
        updateUserIndexes(user, _balances[user]); // release any owed dividends
        uint256 balance = balanceOf(user);
        if (balance != 0) {
            _totalFloat -= balance;
        }
        _dividendsBlacklist[user] = true;
    }

    function removeDividendsBlacklist(address user) internal virtual {
        require(_dividendsBlacklist[user], "Error: account not blacklisted.");
        uint256 balance = balanceOf(user);
        if (balance != 0) {
            _totalFloat += balance;
        }
        _dividendsBlacklist[user] = false;
        updateUserIndexes(user, _balances[user]);
    }

    function isBlacklist(address user) external view returns (bool) {
        return _dividendsBlacklist[user];
    }

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Each yielding savings asset from the protocol initialized
     **/
    struct DividendAssetData {
        uint256 supply;
        uint256 dividendBalance; // last updated
        uint256 index;
        uint256 decimals;
        mapping(address => uint256) users; // user index
        mapping(address => uint256) usersUnclaimedDividends; // user unclaimedd dividneds
    }

    mapping(address => DividendAssetData) internal dividendAssets; // asset mapping
    mapping(uint256 => address) public _dividendAssetsList;

    uint256 internal _dividendAssetsCount;

    uint256 public constant ONE = 1e18;

    /**
     * @dev Adds savings token from protocol to begin hooking into dividendSupply() function
     */
    function addDividendAsset(address asset) internal {
        // console.log("addDividendAsset", asset);
        uint256 dividendAssetsCount = _dividendAssetsCount;
        bool dividendAssetAlreadyAdded = false;
        for (uint256 i = 0; i < dividendAssetsCount; i++)
            if (_dividendAssetsList[i] == asset) {
                dividendAssetAlreadyAdded = true;
            }
        if (!dividendAssetAlreadyAdded) {
            _dividendAssetsList[dividendAssetsCount] = asset;
            DividendAssetData storage dividendAsset = dividendAssets[asset];
            dividendAsset.decimals = IERC20Metadata(asset).decimals();
            dividendAsset.supply = IAvaToken(asset).dividendSupply();
            // console.log("addDividendAsset dividendAsset.supply", dividendAsset.supply);

            dividendAsset.index = calculateDividendAssetIndex(dividendAsset.supply, dividendAsset.supply, dividendAsset.decimals, 1e18);
            // console.log("addDividendAsset dividendAsset.index", dividendAsset.index);
            _dividendAssetsCount = dividendAssetsCount + 1;
        }
    }

    /**
     * @dev Calculates the dividend index from totalFloat()
     * @param totalDividends Address to blacklist
     * @param previousTotalDividends Address to blacklist
     * @param decimals Address to blacklist
     * @param lastIndex Address to blacklist
     */
    function calculateDividendAssetIndex(uint256 totalDividends, uint256 previousTotalDividends, uint256 decimals, uint256 lastIndex) internal view returns (uint256) {
        // console.log("calculateDividendAssetIndex totalDividends", totalDividends);
        // console.log("calculateDividendAssetIndex previousTotalDividends", previousTotalDividends);
        // console.log("calculateDividendAssetIndex lastIndex0", lastIndex);

        uint256 currentFloat = totalFloat();
        // do not divide by zero
        if (previousTotalDividends > totalDividends ||
            totalDividends == 0 ||
            currentFloat == 0
        ) {
            return lastIndex;
        }
        // console.log("calculateDividendAssetIndex lastIndex", lastIndex);

        // console.log("calculateDividendAssetIndex currentFloat", currentFloat);
        uint256 dividendSupplyDelta = totalDividends - previousTotalDividends; // safe from previous check

        return ((dividendSupplyDelta.mul(10**18).div(10**decimals)).wadDiv(currentFloat)).add(lastIndex);

    }

    /**
     * @dev Update a users index for each dividend asset
     **/
    function updateUserIndexes(address user, uint256 previousBalance) internal {
        // console.log("updateUserIndexes start");
        updateDividendAssetData();
        // console.log("updateUserIndexes after updateDividendAssetData");
        for (uint256 i = 0; i < _dividendAssetsCount; i++) {
            address currentAsset = _dividendAssetsList[i];
            DividendAssetData storage dividendAsset = dividendAssets[currentAsset];
            if (dividendAsset.users[user] == 0) {
                dividendAsset.users[user] = dividendAsset.index;
                // console.log("updateUserIndexes dividendAsset.users[user]", dividendAsset.users[user]);
                continue;
            }

            if (dividendAsset.users[user] != dividendAsset.index) {
                // accrue
                //100 * (3.3038461538461538461538461538462 - 1) / 1
                dividendAsset.usersUnclaimedDividends[user] = dividendAsset.usersUnclaimedDividends[user].add(previousBalance.wadMul(dividendAsset.index.sub(dividendAsset.users[user])).mul(10**dividendAsset.decimals).div(10**18));
                /* dividendAsset.usersUnclaimedDividends[user] = dividendAsset.usersUnclaimedDividends[user].add(previousBalance.wadMul(dividendAsset.index.sub(dividendAsset.users[user])).wadDiv(ONE)); */
                // update
                // console.log("updateUserIndexes dividendAsset.usersUnclaimedDividends[user]", dividendAsset.usersUnclaimedDividends[user]);
                dividendAsset.users[user] = dividendAsset.index;
            }
        }
    }

    /**
     * @dev Update a index for each dividend asset
     **/
    function updateDividendAssetData() internal {
        // console.log("updateDividendAssetData start");
        for (uint256 i = 0; i < _dividendAssetsCount; i++) {
            address currentAsset = _dividendAssetsList[i];
            DividendAssetData storage dividendAsset = dividendAssets[currentAsset];
            uint256 previousIndex = dividendAsset.index;
            uint256 previousSupply = dividendAsset.supply;
            dividendAsset.supply = IAvaToken(currentAsset).dividendSupply();
            if (previousSupply < dividendAsset.supply) {
                dividendAsset.index = calculateDividendAssetIndex(dividendAsset.supply, previousSupply, dividendAsset.decimals, previousIndex);
                // console.log("updateDividendAssetData dividendAsset.index", dividendAsset.index);

            }
        }
    }

    /**
     * @dev Return the balance for a dividend asset for a user 
     * balanceOf() equivelent
     **/
    function balanceOfUserDividendAsset(address user, address asset) public view returns (uint256) {
        DividendAssetData storage dividendAsset = dividendAssets[asset];
        // console.log("balanceOfUserDividendAsset start");
        // console.log("balanceOfUserDividendAsset dividendAsset.index", dividendAsset.index);

        uint256 newIndex = calculateDividendAssetIndex(IAvaToken(asset).dividendSupply(), dividendAsset.supply, dividendAsset.decimals, dividendAsset.index);
        // console.log("balanceOfUserDividendAsset newIndex", newIndex);

        uint256 currentUnclaimed = dividendAsset.usersUnclaimedDividends[user];
        // console.log("balanceOfUserDividendAsset currentUnclaimed", currentUnclaimed);

        if (newIndex == dividendAsset.index) {
            return currentUnclaimed;
        }
        uint256 balance = balanceOf(user);
        // console.log("balanceOfUserDividendAsset balance", balance);
        return currentUnclaimed.add(balance.wadMul(newIndex.sub(dividendAsset.users[user])).mul(10**dividendAsset.decimals).div(10**18));
        /* return currentUnclaimed.add(balance.wadMul(newIndex.sub(dividendAsset.users[user])).wadDiv(ONE)); */
    }

    /**
     * @dev Claim dividend asset balance
     **/
    function claimDividend(address asset) public {
        DividendAssetData storage dividendAsset = dividendAssets[asset];
        address user = msg.sender;
        uint256 balance = balanceOf(user);
        updateUserIndexes(user, balance);
        if (dividendAsset.usersUnclaimedDividends[user] > 0) {
            IERC20(asset).transfer(user, dividendAsset.usersUnclaimedDividends[user]);
            dividendAsset.usersUnclaimedDividends[user] = 0;
        }
    }

    /**
     * @dev Claim dividend asset balance for each asset
     **/
    function claimDividends() external {
        uint256 totalDividends;
        for (uint256 i = 0; i < _dividendAssetsCount; i++) {
            address currentAsset = _dividendAssetsList[i];
            totalDividends += balanceOfUserDividendAsset(msg.sender, currentAsset);
        }
        require(totalDividends != 0, "Error: Account dividend balance is zero");

        for (uint256 i = 0; i < _dividendAssetsCount; i++) {
            address currentAsset = _dividendAssetsList[i];
            claimDividend(currentAsset);
        }
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Tracks totalSupply that should be counted towards dividends
     * For example, some addresses are blacklisted so any minted tokens
     * to blacklisted addresses will be voided from totalFloat
     */
    function totalFloat() public view virtual returns (uint256) {
        return _totalFloat;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        // console.log("Token _transfer");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        if (!_dividendsBlacklist[sender]) {
            // console.log("tb_transfer 2");
            updateUserIndexes(sender, senderBalance);
        }
        if (!_dividendsBlacklist[recipient]) {
            // console.log("tb_transfer 3");
            updateUserIndexes(recipient, _balances[recipient]);
        }

        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;

        if (!_dividendsBlacklist[account]) {
            // console.log("_mint ");
            _totalFloat += amount;
        }

        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
      // console.log("_beforeTokenTransfer 1");
      /* if (!_dividendsBlacklist[from]) {
          // console.log("_beforeTokenTransfer 2");
          updateUserIndexes(from);
      }
      if (!_dividendsBlacklist[to]) {
          // console.log("_beforeTokenTransfer 3");
          updateUserIndexes(to);
      } */
      if (_dividendsBlacklist[from] && !_dividendsBlacklist[to]) {
          // console.log("_beforeTokenTransfer ");
          _totalFloat += amount;
      } else if (!_dividendsBlacklist[from] && _dividendsBlacklist[to]) {
          // console.log("_beforeTokenTransfer 5");
          _totalFloat -= amount;
      }
    }

    /* function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (!_dividendsBlacklist[from]) {
            updateUserIndexes(from);
        }
    } */


    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
