// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/** 
 * @title Voting
 * @dev Implements voting process along with vote delegation
 */
contract Voting is Ownable{

    struct Voter {
        bool isRegistered; // if true, that person can vote
        bool hasVoted; // if true, that person already voted
        uint votedProposalId; // index of the voted proposal
    }
    struct Proposal {
        string description; // describe what was the proposal about
        uint voteCount; // number of accumulated votes
    }

    enum WorkflowStatus {
        RegisteringVoters, // Indicates who can vote
        ProposalsRegistrationStarted, // Indicates when people can submit proposals
        ProposalsRegistrationEnded, // Indicates when proposal submission is over
        VotingSessionStarted, // Indicates when voting campaign is opened
        VotingSessionEnded, // Indicates when voting campaign is closed
        VotesTallied // Indicates when the votes are tallied
    }

    address chairpersonAddress;
    string public currentCampaignTitle;
    mapping(address => Voter) private voters;
    address[] private votersAddresses;
    Proposal[] private proposals;
    uint private winningProposalId;
    bool private winnerElected;

    WorkflowStatus currentWorkflowStatus;

    event CampaignInitialized(string message);
    event VoterRegisteredFromHardCodedList(string message);
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event ProposalRegisteredFromHardCodedList(string message);
    event Voted (address voter, uint proposalId);
    event WinnerSelected(uint winners);
    event NoWinnerElected(string message);

    /** 
     * @dev Set the admin to the calling address.
     * @param _newCampaignTitle refers to the chairpersonName given when the contract is initialized.
     * I made this part only for the test, it's not made for production.
     */
    constructor(string memory _newCampaignTitle) onlyOwner {
        chairpersonAddress = msg.sender;
        currentCampaignTitle = _newCampaignTitle;
        emit CampaignInitialized(string.concat("New campaign's initialization complete : ",_newCampaignTitle));
    }

    /** 
     * modifier isCampaignOpened check whether a campaign is on going.
     */
    modifier isCampaignOpened() {
        require(currentWorkflowStatus != WorkflowStatus.RegisteringVoters, "There is no campaign on going. Impossible to close one.");
        _;
    }
    /** 
     * modifier canAddVotersorOpenProposalsRegistration check if the chairperson can open proposals registration or add new voter to the registered list.
     */
    modifier canAddVotersOrOpenProposalsRegistration() {
        require(currentWorkflowStatus == WorkflowStatus.RegisteringVoters, "Impossible to open proposals registration or add new voters at the moment.");
        _;
    }
    /** 
     * modifier canAddNewProposalsOrCloseProposalsRegistration check if the chairperson can close proposals registration or the registered voters can add new proposals.
     */
    modifier canAddNewProposalsOrCloseProposalsRegistration() {
        require(currentWorkflowStatus == WorkflowStatus.ProposalsRegistrationStarted, "Impossible to add new proposals or to close proposals registration at the moment.");
        _;
    }
    /** 
     * modifier canOpenVotingSession check whether the chairperson can open the voting session.
     */
    modifier canOpenVotingSession() {
        require(currentWorkflowStatus == WorkflowStatus.ProposalsRegistrationEnded, "Impossible to open the voting session at the moment.");
        _;
    }
    /** 
     * modifier canCloseVotingSession check whether the voters can vote or the chairperson can close the voting session.
     */
    modifier canVoteorCanCloseVotingSession() {
        require(currentWorkflowStatus == WorkflowStatus.VotingSessionStarted, "Impossible to vote or to close the voting session at the moment.");
        _;
    }
    /** 
     * modifier canVotesBeChecked check whether voters can check what are other voters' votes.
     */
    modifier canVotesBeChecked() {
        require(uint8(currentWorkflowStatus) >= 4, "Impossible to check voter's votes since the voting session hasn't started yet.");
        _;
    }
    /** 
     * modifier canOpenCountingSession check whether the chairperson can open the counting session.
     */
    modifier canOpenCountingSession() {
        require(currentWorkflowStatus == WorkflowStatus.VotingSessionEnded, "Impossible to open the counting session at the moment.");
        _;
    }
    /** 
     * modifier canCountVotes check whether the chairperson can count votes.
     */
    modifier canCountVotes() {
        require(currentWorkflowStatus == WorkflowStatus.VotesTallied, "Impossible to count votes at the moment.");
        _;
    }
    /** 
     * modifier isThereAWinner check whether the chairperson allow voters to check the results.
     */
    modifier isThereAWinner() {
        require((currentWorkflowStatus == WorkflowStatus.VotesTallied && winnerElected), "There is no winner in this election. Please, start over again.");
        _;
    }
    /** 
     * modifier oneOrMoreVotersRegistered check whether there is at least one voter registered.
     */
    modifier oneOrMoreVotersRegistered() {
        require(votersAddresses.length >= 1, "Impossible to start registering proposals because no voter is registered.");
        _;
    }
    /** 
     * modifier oneOrMoreProposalsRegistered check whether there is at least one proposal registered.
     */
    modifier oneOrMoreProposalsRegistered() {
        require(proposals.length >= 1, "Impossible to stop proposals registration because no proposal has been registered yet.");
        _;
    }
    /** 
     * modifier canAddThisNewVoter check whether the address isn't registered as a voter.
     */
    modifier canAddThisNewVoter(address _addr) {
        require((voters[_addr].isRegistered == false), "This address has already been registered as an eligible voter.");
        _;
    }
    /** 
     * modifier isUserARegisteredVoter check whether the caller egistered a voter.
     */
    modifier isUserARegisteredVoter {
        require((voters[msg.sender].isRegistered == true), "The provided address is not registered as an eligible voter.");
        _;
    }
    /** 
     * modifier isUserAllowedToVote check whether the address is registered as an eligible voter and hasn't voted yet.
     */
    modifier isUserAllowedToVote() {
        require((voters[msg.sender].isRegistered == true && voters[msg.sender].hasVoted == false), "Your address is not registered as an eligible voter (you can't vote or see other voters' choices) or your vote has already been registered.");
        _;
    }
    /** 
     * modifier isAddressAllowedToVote check whether the address is registered as an eligible voter and hasn't voted yet.
     */
    modifier isAddressAllowedToVote(address _addr) {
        require(voters[_addr].isRegistered == true, "The provided address doesn't match in the registered voters list.");
        _;
    }
    /** 
     * modifier hasAddressVoted check whether the address has voted yet.
     */
    modifier hasAddressVoted(address _addr) {
        require(voters[_addr].hasVoted == true, "The provided address hasn't voted yet.");
        _;
    }
    /** 
     * modifier doesVoteIdMatch check whether the vote id matches in the proposals list.
     */
    modifier doesVoteIdMatch(uint _voteId) {
        require(_voteId < proposals.length, "The provided id doesn't match in the proposals list. Please, try another one.");
        _;
    }

    /** 
     * modifier isProposalAlreadyRegistered check whether the provided proposal has already been registered.
     */
    modifier isProposalAlreadyRegistered(string memory _newProposalDescription) {
        for (uint i = 0; i < proposals.length; i++) {
            require(keccak256(abi.encodePacked(proposals[i].description)) != keccak256(abi.encodePacked(_newProposalDescription)),"The provided proposition has already been registered.");
        }
        _;
    }

    /** 
     * @dev Calls modifyWorkflowStatus() function anables the chairperson to change the campaign current workflow status.
     * @param _newStatusCode index of workflowStatus in the WorkflowStatus enum.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function _modifyWorkflowStatus(uint8 _newStatusCode) internal {
        WorkflowStatus previousState = currentWorkflowStatus;
        if(_newStatusCode == 0){
            currentWorkflowStatus = WorkflowStatus.RegisteringVoters;
            emit WorkflowStatusChange(previousState, currentWorkflowStatus);
        } else if(_newStatusCode == 1){
            currentWorkflowStatus = WorkflowStatus.ProposalsRegistrationStarted;
            emit WorkflowStatusChange(previousState, currentWorkflowStatus);
        } else if(_newStatusCode == 2){
            currentWorkflowStatus = WorkflowStatus.ProposalsRegistrationEnded;
            emit WorkflowStatusChange(previousState, currentWorkflowStatus);
        } else if(_newStatusCode == 3){
            currentWorkflowStatus = WorkflowStatus.VotingSessionStarted;
            emit WorkflowStatusChange(previousState, currentWorkflowStatus);
        } else if(_newStatusCode == 4){
            currentWorkflowStatus = WorkflowStatus.VotingSessionEnded;
            emit WorkflowStatusChange(previousState, currentWorkflowStatus);
        } else if(_newStatusCode == 5){
            currentWorkflowStatus = WorkflowStatus.VotesTallied;
            emit WorkflowStatusChange(previousState, currentWorkflowStatus);
        } else {
            revert("Invalid workflow status code.");
        }
    }
    
    /** 
     * @dev Calls closeCampaign() function anables the chairperson to close the current campaign.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function closeCampaign() public onlyOwner isCampaignOpened {
        _resetCampaign();
        _modifyWorkflowStatus(0);
    }
    /** 
     * @dev Calls startRegisterProposals() function anables the chairperson to open proposals registration.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function startRegisterProposals() public onlyOwner canAddVotersOrOpenProposalsRegistration oneOrMoreVotersRegistered {
        _modifyWorkflowStatus(1);
    }
    /** 
     * @dev Calls stopRegisterProposals() function anables the chairperson to close proposals registration.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function stopRegisterProposals() public onlyOwner canAddNewProposalsOrCloseProposalsRegistration oneOrMoreProposalsRegistered {
        _modifyWorkflowStatus(2);
    }
    /** 
     * @dev Calls startVoting() function anables the chairperson to open the voting session.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function startVoting() public onlyOwner canOpenVotingSession {
        _modifyWorkflowStatus(3);
    }
    /** 
     * @dev Calls stopVoting() function anables the chairperson to close the voting session.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function stopVoting() public onlyOwner canVoteorCanCloseVotingSession {
        _modifyWorkflowStatus(4);
    }
    /** 
     * @dev Calls startCounting() function anables the chairperson to start the votes counting.
     * modifier onlyOwner form Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function startCounting() public onlyOwner canOpenCountingSession {
        _modifyWorkflowStatus(5);
        _countVotes();
    }

    /** 
     * @dev Calls showCurrentWorkflowStatus() function show the campaign current workflow status.
     * @return a string indicating the new current campaign status.
     */
    function showCurrentWorkflowStatus() external view returns (string memory) {
        WorkflowStatus temp = currentWorkflowStatus;
        if (temp == WorkflowStatus.RegisteringVoters){
            return "Registering voters session on going.";
        } else if (temp == WorkflowStatus.ProposalsRegistrationStarted) {
            return "Registering voters session has ended. Proposals registration session on going.";
        } else if (temp == WorkflowStatus.ProposalsRegistrationEnded) {
            return "Proposals registration session over.";
        } else if (temp == WorkflowStatus.VotingSessionStarted) {
            return "Voting session on going.";
        } else if (temp == WorkflowStatus.VotingSessionEnded) {
            return "Voting session over.";
        } else if (temp == WorkflowStatus.VotesTallied) {
            return "Talling votes session on going ; you may check the results.";
        } else {
            return "No campaign on going.";
        }
    }

    /** 
     * @dev Calls addVoter() function anables the chairperson to add a voter to the voters mapping.
     * @param _addr to make an new voter linked to the address given.
     * modifier onlyOwner from Openzeppelin's contract indicating the function is only usable with the contract creator's address.
     */
    function addVoter(address _addr) public onlyOwner canAddVotersOrOpenProposalsRegistration canAddThisNewVoter(_addr) {
        Voter memory newVoter = Voter(true, false, 0);
        voters[_addr] = newVoter;
        votersAddresses.push(_addr);
        emit VoterRegistered(_addr);
    }

    /** 
     * @dev Calls getVotersList() function to get the whole registered voters addresses list.
     * @return votersList_ an coma separated list of all registered voters.
     */
    function getVotersList() external view returns (address[] memory votersList_) {
        votersList_ = votersAddresses;
        return votersList_;
    }   

    /** 
     * @dev Calls addNewProposal() function to add an new proposal to the proposals list.
     * @param _newProposalDescription description of the added proposal.
     */
    function addNewProposal(string memory _newProposalDescription) public canAddNewProposalsOrCloseProposalsRegistration isUserAllowedToVote isProposalAlreadyRegistered(_newProposalDescription) {
        uint propId = proposals.length;
        Proposal memory newProposal = Proposal(_newProposalDescription,0);
        proposals.push(newProposal);
        emit ProposalRegistered(propId);
    }

    /** 
     * @dev Calls getProposalsList() function to get the whole proposals list.
     * @return proposals an coma separated list of all registered proposals.
     */
    function getProposalsList() external view returns (Proposal[] memory) {
        return proposals;
    } 

    /** 
     * @dev Calls vote() function anables registered voters to vote for their prefered proposal.
     * Only one vote per voter allowed.
     */
    function vote(uint _voteId) public canVoteorCanCloseVotingSession isUserAllowedToVote doesVoteIdMatch(_voteId) {
        voters[msg.sender].votedProposalId = _voteId;
        voters[msg.sender].hasVoted = true;
        proposals[_voteId].voteCount++;
        emit Voted(msg.sender, _voteId);
    }

    /** 
     * @dev Calls getVotersVotes() function to get the proposal id of a voter's vote.
     * @return a uint indicating the id of the choosen proposal according to the voter's address.
     */
    function getVotersVotes(address _voterAddress) external view isUserARegisteredVoter canVotesBeChecked isAddressAllowedToVote(_voterAddress) hasAddressVoted(_voterAddress) returns (uint) {
        return voters[_voterAddress].votedProposalId;
    }   

    /** 
     * @dev Computes the winning proposal taking all previous votes into account.
     * Then, set the winningProposalId with the winners' id.
     */
    function _countVotes() internal {
        uint winningVoteCount = 0;
        // First, the maximum vote count of the proposals list is determined.
        for (uint p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
                winningVoteCount = proposals[p].voteCount;
            }
        }
        // Then, checking is made to find the proposal with that one number.
        // If many proposals do have the same votes count, no one is elected and the vote has to start over again.
        if (winningVoteCount > 0) {
            uint winningProposalsNumber = 0;
            for (uint p = 0; p < proposals.length; p++) {
                if (proposals[p].voteCount == winningVoteCount) {
                    winningProposalId = p;
                    winningProposalsNumber++;
                }
            }
            if(winningProposalsNumber > 1) {
                emit NoWinnerElected("Two or more proposals have the same votes count. None is elected. The vote must start over again. Maybe, try new proposals.");
            } else {
                winnerElected = true;
                emit WinnerSelected(winningProposalId);
            }
        } else {
            emit NoWinnerElected("None of the proposals has been choosen as the winning one. The vote must start over again. Maybe, try new proposals.");
        }
    }

    /** 
     * @dev Calls getWinner() function to get the index of the winners contained in the proposals array and then
     * @return winningProposalId the winner's id.
     */
    function getWinner() external view isThereAWinner returns (uint) {
        return winningProposalId;
    }

    /** 
     * @dev Calls getWinnerFullDetails() function to get the winning proposal details.
     */
    function getWinnerFullDetails() external view isThereAWinner returns (string memory) {
        return string.concat("The id ",Strings.toString(winningProposalId)," (",proposals[winningProposalId].description,") won with ",Strings.toString(proposals[winningProposalId].voteCount)," votes.");
    }

    /** 
     * @dev Calls _resetCampaign() function reset both voters' addresses array and the voters' infos mapping.
     */
    function _resetCampaign() internal {
        for (uint i = 0; i < votersAddresses.length; i++) {
            // iterate over the voters' addresses array to iterate over the voters' mapping and reset all to value
            voters[votersAddresses[i]].isRegistered = false;
            voters[votersAddresses[i]].hasVoted = false;
            voters[votersAddresses[i]].votedProposalId = 0;
        }
        delete proposals;
    }

    /** 
     * @dev Calls showFirstVoterInfo() function is only used in development to check whether the voters mapping is reset or not (only for the first entry).
     * It returns the first voters infos.
     */
    function showFirstVoterInfo() external view onlyOwner returns (bool,bool,uint) {
        return(voters[votersAddresses[0]].isRegistered,voters[votersAddresses[0]].hasVoted,voters[votersAddresses[0]].votedProposalId);
    }
}
