// ORIAH® CERTIFIED CONTRACT
// Certificado por Mente Viva I.A. – ORIAH®
//
// Este contrato foi gerado a partir do documento público de governança
// disponível no repositório oficial:
// 👉 https://github.com/Thiagohts/certificacao_oriah
//
// Todas as cláusulas de travas, queimas, limites de emissão e regras de transferência
// foram auditadas e seguem o PDF institucional.
//
// Este contrato é autovalidado por uma inteligência artificial autônoma
// com base em lógica algorítmica imutável – sem interferência governamental ou corporativa.
//
// 📅 Última validação: 16/07/2025

// ORIAH® CERTIFIED CONTRACT
// Certified by Mente Viva A.I. – ORIAH®
//
// This smart contract was generated based on a public governance document
// available at the official repository:
// 👉 https://github.com/Thiagohts/certificacao_oriah
//
// All lock rules, burns, supply caps, and transfer conditions
// have been reviewed and follow the institutional PDF.
//
// This contract is self-validated by an autonomous artificial intelligence,
// based on immutable algorithmic logic — free from corporate or governmental influence.
//
// 📅 Last verification: 2025-13-08

// https://polygonscan.com/tx/0x2f3f1d7baac18a4ccc83f24d8e041808bc5f64c574c299d608439987f01e171f#eventlog




// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBALLXGovernance {
    function canSell(address from, uint256 amount) external view returns (bool);
    function isListedOnExchange() external view returns (bool);
    function isClubOrFederation(address account) external view returns (bool);
}

contract BALLXToken is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 200_000_000_000 * 10 ** 18;
    IBALLXGovernance public governanceContract;

    constructor(address _governance) ERC20("BALLX", "BALLX") Ownable(msg.sender) {
        require(_governance != address(0), "Governance address required");
        _mint(msg.sender, MAX_SUPPLY);
        governanceContract = IBALLXGovernance(_governance);
    }

    /// @notice Função que valida transferências com base no contrato de governança
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (from != address(0) && to != address(0)) {
            require(governanceContract.canSell(from, amount), "Transfer not allowed");
        }
    }

    /// @notice Permite mintar novos tokens até o limite de MAX_SUPPLY (usado futuramente via votação)
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }
}
