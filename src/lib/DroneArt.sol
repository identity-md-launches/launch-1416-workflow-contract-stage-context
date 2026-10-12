// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Internal-only renderer: inlined into PulseDrone, with no linked library or external renderer.
library DroneArt {
    using Strings for uint256;

    struct Metadata {
        uint256 tokenId;
        uint8 caste;
        uint8 color;
        uint8 eyes;
        bool alive;
        uint256 streak;
        uint256 bestStreak;
        uint256 totalBeats;
        uint8 rank;
        uint256 staked;
    }

    function tokenURI(Metadata memory m) internal pure returns (string memory) {
        string memory json = string.concat(
            '{"name":"',
            callSign(m.tokenId),
            '","description":"PULSE - Keep the Swarm Alive. A soulbound Drone. Beat every 20 to 48 hours; stake PULSE to rise through the Hive.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg(m))),
            '","attributes":[',
            _textAttribute("Caste", casteName(m.caste)),
            ",",
            _textAttribute("Color", colorName(m.color)),
            ",",
            _textAttribute("Eyes", eyeName(m.eyes)),
            ",",
            _textAttribute("Status", m.alive ? "Alive" : "Dormant"),
            ",",
            _numberAttribute("Streak", m.streak),
            ",",
            _numberAttribute("Best Streak", m.bestStreak),
            ",",
            _numberAttribute("Total Beats", m.totalBeats),
            ",",
            _textAttribute("Rank", rankName(m.rank)),
            ",",
            _textAttribute("Staked", formatPulse(m.staked)),
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function svg(Metadata memory m) internal pure returns (string memory) {
        string memory accent = m.alive ? "#FBBF24" : "#A3A3A3";
        string memory ink = m.alive ? "#FEF3C7" : "#D4D4D4";
        string memory body = m.alive ? palette(m.color) : "#737373";
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512" role="img">',
            "<title>",
            callSign(m.tokenId),
            " - ",
            m.alive ? "Alive" : "Dormant",
            '</title><rect width="512" height="512" rx="32" fill="',
            m.alive ? "#0C0A09" : "#0A0A0A",
            '"/><path d="M0 100H512M0 412H512M100 0V512M412 0V512" stroke="',
            m.alive ? "#292018" : "#262626",
            '" stroke-width="1"/>',
            _glow(m.alive),
            _auras(m.streak, accent),
            '<polygon points="256,126 365,189 365,315 256,378 147,315 147,189" fill="',
            body,
            '" stroke="',
            accent,
            '" stroke-width="3"/><polygon points="256,144 349,198 349,306 256,360 163,306 163,198" fill="none" stroke="',
            ink,
            '" stroke-opacity="0.35"/><path d="M183 223H329V277H183Z" fill="#171717"/>',
            '<g fill="',
            ink,
            '">',
            _eyes(m.eyes),
            '</g><g transform="translate(236 294)" fill="none" stroke="',
            ink,
            '" stroke-width="3" stroke-linejoin="round" data-caste="',
            casteName(m.caste),
            '">',
            _emblem(m.caste),
            "</g>",
            _badge(m.rank, accent),
            '<g font-family="monospace" text-anchor="middle" fill="',
            ink,
            '"><text x="256" y="58" font-size="24" letter-spacing="4">',
            callSign(m.tokenId),
            '</text><text x="256" y="88" font-size="12" letter-spacing="3">',
            casteName(m.caste),
            '</text><text x="256" y="437" font-size="16">',
            m.alive ? "ALIVE" : "DORMANT",
            " / STREAK ",
            m.streak.toString(),
            '</text><text x="256" y="471" font-size="11" letter-spacing="3">PULSE / KEEP THE SWARM ALIVE</text></g></svg>'
        );
    }

    function callSign(uint256 tokenId) internal pure returns (string memory) {
        string memory digits = tokenId.toString();
        if (tokenId < 10) return string.concat("DRONE-000", digits);
        if (tokenId < 100) return string.concat("DRONE-00", digits);
        if (tokenId < 1000) return string.concat("DRONE-0", digits);
        return string.concat("DRONE-", digits);
    }

    function casteName(uint8 caste) internal pure returns (string memory) {
        if (caste == 0) return "Worker";
        if (caste == 1) return "Scout";
        if (caste == 2) return "Guard";
        return "Builder";
    }

    function rankName(uint8 rank) internal pure returns (string memory) {
        if (rank == 0) return "Larva";
        if (rank == 1) return "Worker";
        if (rank == 2) return "Guard";
        if (rank == 3) return "Royal Guard";
        return "Queen's Guard";
    }

    function colorName(uint8 color) internal pure returns (string memory) {
        if (color == 0) return "Amber";
        if (color == 1) return "Gold";
        if (color == 2) return "Copper";
        if (color == 3) return "Coral";
        if (color == 4) return "Teal";
        if (color == 5) return "Azure";
        if (color == 6) return "Violet";
        return "Jade";
    }

    function palette(uint8 color) internal pure returns (string memory) {
        if (color == 0) return "#D97706";
        if (color == 1) return "#CA8A04";
        if (color == 2) return "#B87333";
        if (color == 3) return "#E76F51";
        if (color == 4) return "#0D9488";
        if (color == 5) return "#0284C7";
        if (color == 6) return "#8B5CF6";
        return "#15803D";
    }

    function eyeName(uint8 eyes) internal pure returns (string memory) {
        if (eyes == 0) return "Twin";
        if (eyes == 1) return "Visor";
        if (eyes == 2) return "Triad";
        if (eyes == 3) return "Diamond";
        if (eyes == 4) return "Scanner";
        return "Cross";
    }

    /// @dev Exact human-readable PULSE, retaining all 18 fractional places when nonzero.
    function formatPulse(uint256 amount) internal pure returns (string memory) {
        string memory whole = (amount / 1 ether).toString();
        uint256 fraction = amount % 1 ether;
        if (fraction == 0) return whole;
        bytes memory padded = bytes((1 ether + fraction).toString());
        padded[0] = ".";
        return string.concat(whole, string(padded));
    }

    function _glow(bool alive) private pure returns (string memory) {
        if (!alive) return "";
        return '<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="12"/></filter></defs><polygon points="256,126 365,189 365,315 256,378 147,315 147,189" fill="#F59E0B" filter="url(#glow)" opacity="0.55"><animate attributeName="opacity" values="0.25;0.75;0.25" dur="4s" repeatCount="indefinite"/></polygon>';
    }

    function _auras(uint256 streak, string memory accent) private pure returns (string memory result) {
        if (streak < 7) return "";
        result = string.concat(
            '<g fill="none" stroke="',
            accent,
            '" stroke-width="2"><polygon data-aura="1" points="256,112 377,182 377,322 256,392 135,322 135,182"/>'
        );
        if (streak >= 30) {
            result = string.concat(
                result,
                '<polygon data-aura="2" opacity="0.65" points="256,101 387,177 387,327 256,403 125,327 125,177"/>'
            );
        }
        if (streak >= 100) {
            result = string.concat(
                result,
                '<polygon data-aura="3" opacity="0.35" points="256,90 397,171 397,333 256,414 115,333 115,171"/>'
            );
        }
        return string.concat(result, "</g>");
    }

    function _eyes(uint8 eyes) private pure returns (string memory) {
        if (eyes == 0) return '<circle cx="224" cy="250" r="10"/><circle cx="288" cy="250" r="10"/>';
        if (eyes == 1) return '<rect x="202" y="245" width="108" height="10" rx="5"/>';
        if (eyes == 2) {
            return '<circle cx="220" cy="250" r="7"/><circle cx="256" cy="250" r="7"/><circle cx="292" cy="250" r="7"/>';
        }
        if (eyes == 3) return '<path d="M224 237L237 250L224 263L211 250ZM288 237L301 250L288 263L275 250Z"/>';
        if (eyes == 4) return '<path d="M203 239H309V243H203ZM211 249H301V253H211ZM219 259H293V263H219Z"/>';
        return '<path d="M219 237H229V245H237V255H229V263H219V255H211V245H219ZM283 237H293V245H301V255H293V263H283V255H275V245H283Z"/>';
    }

    function _emblem(uint8 caste) private pure returns (string memory) {
        if (caste == 0) return '<path d="M6 6L34 34M34 6L6 34M3 13L13 3M27 37L37 27"/>';
        if (caste == 1) return '<path d="M20 2L37 37L20 28L3 37ZM20 2V28"/>';
        if (caste == 2) return '<path d="M4 5L20 1L36 5V21L20 39L4 21ZM20 9V29M11 19H29"/>';
        return '<path d="M3 10H37V34H3ZM3 22H37M20 10V22M12 22V34M28 22V34"/>';
    }

    function _badge(uint8 rank, string memory accent) private pure returns (string memory) {
        if (rank == 0) return "";
        string memory label = rank == 1 ? "W" : rank == 2 ? "G" : rank == 3 ? "RG" : "QG";
        return string.concat(
            '<g data-rank="',
            rankName(rank),
            '"><circle cx="456" cy="56" r="25" fill="#171717" stroke="',
            accent,
            '" stroke-width="2"/><text x="456" y="61" font-family="monospace" font-size="14" text-anchor="middle" fill="',
            accent,
            '">',
            label,
            "</text></g>"
        );
    }

    function _textAttribute(string memory trait, string memory value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', trait, '","value":"', value, '"}');
    }

    function _numberAttribute(string memory trait, uint256 value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', trait, '","value":', value.toString(), "}");
    }
}
