// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IEntropy {
    function requestWithCallback(
        address provider,
        bytes32 userRandomNumber
    ) external payable returns (uint64 assignedSequenceNumber);
    function revealWithCallback(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRandomNumber,
        bytes32 providerRevelation
    ) external;
    function getFee(address provider) external view returns (uint256);
}

abstract contract IEntropyConsumer {
    // This method is called by Entropy to provide the random number to the consumer.
    // It asserts that the msg.sender is the Entropy contract. It is not meant to be
    // override by the consumer.
    function _entropyCallback(
        uint64 sequence,
        address provider,
        bytes32 randomNumber
    ) external {
        address entropy = getEntropy();
        require(entropy != address(0), "Entropy address not set");
        require(msg.sender == entropy, "Only Entropy can call this function");

        entropyCallback(sequence, provider, randomNumber);
    }

    // getEntropy returns Entropy contract address. The method is being used to check that the
    // callback is indeed from Entropy contract. The consumer is expected to implement this method.
    // Entropy address can be found here - https://docs.pyth.network/entropy/contract-addresses
    function getEntropy() internal view virtual returns (address);

    // This method is expected to be implemented by the consumer to handle the random number.
    // It will be called by _entropyCallback after _entropyCallback ensures that the call is
    // indeed from Entropy contract.
    function entropyCallback(
        uint64 sequence,
        address provider,
        bytes32 randomNumber
    ) internal virtual;
}

contract EntropyMock is IEntropy {
    address sender;

    function requestWithCallback(
        address provider,
        bytes32 userRandomNumber
    ) public payable override returns (uint64) {
        require(provider != address(0), "Provider cannot be zero address");
        require(userRandomNumber != bytes32(0), "User random number cannot be zero");
        sender = msg.sender;

        return uint64(block.number);
    }
    
    function revealWithCallback(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRandomNumber,
        bytes32 providerRevelation
    ) public override {
        require(sender != address(0), "Sender cannot be zero address");
        require(provider != address(0), "Provider cannot be zero address");
        require(userRandomNumber != bytes32(0), "User random number cannot be zero");
        require(providerRevelation != bytes32(0), "Provider revelation cannot be zero");

        IEntropyConsumer(sender)._entropyCallback(
            sequenceNumber,
            provider,
            userRandomNumber
        );
    }

    function getFee(address provider) external pure returns (uint256) {
        require(provider != address(0), "Provider cannot be zero address");
        return 100;
    }
}