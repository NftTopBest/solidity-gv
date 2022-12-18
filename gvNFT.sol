// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract GitVerseNFT is ERC1155, Ownable, Pausable, ERC1155Supply {
    using Counters for Counters.Counter;
    Counters.Counter public tokenIdCounter;

    uint256 public CT_Price = 0.0001 ether;
    uint256 public votePrice = 0.01 ether;

    mapping(uint256 => string) public tokenURIMap;
    mapping(uint256 => address) public tokenOwnerMap;

    mapping(uint256 => uint256) public depsCountMap; // tokenId => count
    mapping(uint256 => mapping(string => uint256)) public depsVersionCountMap; // tokenId => version => count

    // vote
    mapping(address => uint256) public userTotalVoteUpCountMap; // userAddress => userTotalVoteUpAmount
    mapping(uint256 => string[]) public voteUpCIDArrayMap; // tokenId => voteUpCID[], store all cid for every token's voteUp

    // comment
    mapping(uint256 => string[]) public commentCIDArrayMap; // tokenId => commentCID[], store all cid for every token's comment
    mapping(address => string[]) public userCommentCIDArrayMap; // userAddress => commentCID[], store all comment cid for every user

    function getTokenDataList(
        uint256 start,
        uint256 limit
    )
        public
        view
        returns (
            string[] memory tokenURIs,
            uint256[] memory voteUpCounts,
            uint256[] memory commentCounts
        )
    {
        uint256 lens = uint256(tokenIdCounter._value - start);
        if (lens < limit) {
            limit = lens;
        }

        tokenURIs = new string[](limit);
        voteUpCounts = new uint256[](limit);
        commentCounts = new uint256[](limit);

        for (uint256 i = 0; i < limit; i++) {
            tokenURIs[i] = tokenURIMap[start + i];
            voteUpCounts[i] = totalSupply(start + i);
            commentCounts[i] = commentCIDArrayMap[start + i].length;
        }
    }

    function getList(
        uint256 dataType,
        uint256 tokenId,
        uint256 start,
        uint256 limit
    ) public view returns (string[] memory arr_) {
        string[] memory all = voteUpCIDArrayMap[tokenId];
        if (dataType == 1) {
            all = commentCIDArrayMap[tokenId];
        }

        uint256 lens = all.length - start;
        if (lens < limit) {
            limit = lens;
        }
        arr_ = new string[](limit);

        for (uint256 i = 0; i < limit; i++) {
            arr_[i] = all[start + i];
        }
    }

    /* solhint-disable func-visibility */
    constructor() ERC1155("") {
        _setURI("");
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function uri(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        string memory tokenURI = tokenURIMap[tokenId];
        return tokenURI;
    }

    event AddPkg(uint256 tokenId);

    function addPkg(
        uint256 basicPrice,
        uint256 inviteCommission,
        string memory metadataCID
    ) public payable whenNotPaused {
        require(bytes(metadataCID).length > 0, "metadataCID is empty");
        require(
            inviteCommission <= 1000,
            "inviteCommission must smaller than 10%"
        );
        require(
            msg.value >= createTokenPrice,
            "insufficient funds for createToken"
        );

        address createdBy = _msgSender();

        uint256 tokenId = tokenIdCounter.current();
        tokenIdCounter.increment();

        tokenURIMap[tokenId] = metadataCID;
        tokenOwnerMap[tokenId] = createdBy;
        basicPriceMap[tokenId] = basicPrice;
        inviteCommissionMap[tokenId] = inviteCommission;
        tokenOwnByMap[createdBy].push(tokenId);

        emit AddPkg(tokenId);
    }

    function updatePkg(
        uint256 tokenId,
        uint256 basicPrice,
        uint256 inviteCommission,
        string memory metadataCID
    ) public whenNotPaused {
        address createdBy = _msgSender();
        require(
            tokenOwnerMap[tokenId] == createdBy,
            "you are not the token creator"
        );
        require(bytes(metadataCID).length > 0, "metadataCID is empty");
        require(
            inviteCommission <= 1000,
            "inviteCommission must smaller than 10%"
        );

        tokenURIMap[tokenId] = metadataCID;
        basicPriceMap[tokenId] = basicPrice;
        inviteCommissionMap[tokenId] = inviteCommission;
    }

    // 新建项目，提交名字、描述、logo、及CID, 依赖的 tokenId，版本号
    event CreateToken(
        uint256 indexed tokenId,
        address indexed createdBy,
        string indexed name,
        string description,
        string image,
        string metadataCID
    );

    function createToken(
        string memory name,
        string memory description,
        string memory image,
        uint256[] memory depsTokenIds,
        string[] memory depsVersions, // 输入的是 depsTokenId 的 version 信息的 CID 即可，此 IPFS 文件存储了该版本的详细信息
        string memory metadataCID
    ) public payable whenNotPaused {
        require(bytes(metadataCID).length > 0, "metadataCID is empty");
        require(msg.value >= CT_Price, "insufficient funds for createToken");

        address createdBy = _msgSender();

        uint256 tokenId = tokenIdCounter.current();
        tokenIdCounter.increment();

        tokenURIMap[tokenId] = metadataCID;
        tokenOwnerMap[tokenId] = createdBy;
        uint256 lens = depsTokenIds.length;
        for (uint256 i = 0; i < lens; i++) {
            depsCountMap[depsTokenIds[i]]++; // 记录该项目被依赖次数，后续映射 ERC721 时用到
            depsVersionCountMap[depsTokenIds[i]][depsVersions[i]]++; // 记录该项目该版本被依赖次数，后续映射 ERC721 时用到
        }
    }

    function updateToken(
        uint256 tokenId,
        uint256[] memory depsTokenIds,
        string[] memory depsVersions, // 输入的是 depsTokenId 的 version 信息的 CID 即可，此 IPFS 文件存储了该版本的详细信息
        string memory metadataCID
    ) public whenNotPaused {
        require(bytes(metadataCID).length > 0, "metadataCID is empty");
        address createdBy = _msgSender();
        require(
            tokenOwnerMap[tokenId] == createdBy,
            "you are not the token creator"
        );

        tokenURIMap[tokenId] = metadataCID;
        tokenOwnerMap[tokenId] = createdBy;
        uint256 lens = depsTokenIds.length;
        for (uint256 i = 0; i < lens; i++) {
            depsCountMap[depsTokenIds[i]]++; // 记录该项目被依赖次数，后续映射 ERC721 时用到
            depsVersionCountMap[depsTokenIds[i]][depsVersions[i]]++; // 记录该项目该版本被依赖次数，后续映射 ERC721 时用到
        }
    }

    event VoteUp(
        address indexed createdBy,
        uint256 indexed tokenId,
        uint256 amount
    );
    event CreateComment(
        address indexed createdBy,
        uint256 indexed tokenId,
        string commentCID
    );

    function voteUp(
        uint256 tokenId,
        uint256 amount,
        string memory voteUpCID,
        string memory commentCID
    ) public payable whenNotPaused {
        require(bytes(tokenURIMap[tokenId]).length > 0, "token not create yet");
        require(
            msg.value >= votePrice * amount,
            "insufficient funds for createToken"
        );

        address createdBy = _msgSender();

        // voteUp
        _mint(createdBy, tokenId, amount, "");
        userTotalVoteUpCountMap[createdBy] += amount;
        voteUpCIDArrayMap[tokenId].push(voteUpCID);
        emit VoteUp(createdBy, tokenId, amount);

        // comment
        if (bytes(commentCID).length > 0) {
            commentCIDArrayMap[tokenId].push(commentCID);
            userCommentCIDArrayMap[createdBy].push(commentCID);
            emit CreateComment(createdBy, tokenId, commentCID);
        }
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
