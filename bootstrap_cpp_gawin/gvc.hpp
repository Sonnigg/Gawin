#pragma once

#include "glexer.hpp"
#include <vector>
#include <string>
#include <algorithm>
#include <iostream>

// ============================================================================
// Implementation of the 'gvc' module
// ============================================================================
namespace gvc {

/**
 * Checks and corrects visibility handles for a collection of tokens.
 */
inline std::vector<glexer::Token> check_visibility(std::vector<glexer::Token> corrected) {
    std::vector<std::string> public_table;
    std::vector<std::string> exposed_table;
    std::vector<std::string> internal_table;

    // Helper lambda to mimic V's 'in' operator for vectors
    auto contains = [](const std::vector<std::string>& table, const std::string& item) {
        return std::find(table.begin(), table.end(), item) != table.end();
    };

    for (size_t idx = 0; idx < corrected.size(); ++idx) {
        auto kind = corrected[idx].kind;
        const auto& lit = corrected[idx].lit;

        bool next1_exists = (idx + 1) < corrected.size();
        bool next2_exists = (idx + 2) < corrected.size();

        // =========================
        // Handle `pub`
        // =========================
        if (kind == glexer::TokenType::key_pub && next1_exists) {
            auto next_kind = corrected[idx + 1].kind;

            switch (next_kind) {
                case glexer::TokenType::key_const:
                case glexer::TokenType::key_enum:
                case glexer::TokenType::key_struct:
                case glexer::TokenType::key_func:
                case glexer::TokenType::key_variant: {
                    if (next2_exists && corrected[idx + 2].kind == glexer::TokenType::ident) {
                        std::string name = corrected[idx + 2].lit;

                        if (!(contains(exposed_table, name) || contains(internal_table, name))) {
                            public_table.push_back(name);
                        }
                    }
                    break;
                }

                case glexer::TokenType::ident: {
                    std::string name = corrected[idx + 1].lit;

                    if (!(contains(exposed_table, name) || contains(internal_table, name))) {
                        public_table.push_back(name);
                    }
                    break;
                }

                default:
                    break;
            }

            continue;
        }

        // =========================
        // Handle identifiers
        // =========================
        if (kind == glexer::TokenType::ident) {
            if (contains(public_table, lit)) {
                corrected[idx].extra_vis = glexer::VisibilityHandle{
                    /*.builtin =*/ false,
                    /*.is_public =*/ true,
                    /*.exposed =*/ false,
                    /*.internal =*/ false
                };
            } 
            else if (contains(exposed_table, lit) || !(contains(public_table, lit) || contains(internal_table, lit))) {
                corrected[idx].extra_vis = glexer::VisibilityHandle{
                    /*.builtin =*/ false,
                    /*.is_public =*/ false,
                    /*.exposed =*/ true,
                    /*.internal =*/ false
                };
            } 
            else if (contains(internal_table, lit)) {
                corrected[idx].extra_vis = glexer::VisibilityHandle{
                    /*.builtin =*/ false,
                    /*.is_public =*/ false,
                    /*.exposed =*/ false,
                    /*.internal =*/ true
                };
            } 
            else {
                std::cerr << "Identifier `" << lit << "` could not be mapped to a visibility level.\n";
            }
        }
    }

    return corrected;
}

} // namespace gvc