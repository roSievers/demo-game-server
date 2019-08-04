//! Implementation of the game rules

use std::collections::HashSet;
use std::iter::FromIterator;

#[derive(Clone, Debug, PartialEq, Eq)]
struct Nim {
    tokens: Vec<TokenState>,
    current_player: u8,
    player_count: u8,
    last_token_taken_by: Option<u8>,
}

#[derive(Clone)]
struct NimAction {
    token_indices: HashSet<usize>,
}

impl NimAction {
    fn from_vec(token_indices: Vec<usize>) -> Self {
        NimAction {
            token_indices: HashSet::from_iter(token_indices),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum NimError {
    TokenAlreadyMissing,
    TokenOutOfBounds,
    ToManyTokens,
    NotEnoughtTokens,
    GameAlreadyOver,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TokenState {
    TokenPresent,
    TokenMissing,
}

impl Nim {
    fn new(token_count: usize, player_count: u8) -> Self {
        Nim {
            tokens: vec![TokenState::TokenPresent; token_count],
            current_player: 0,
            player_count,
            last_token_taken_by: None,
        }
    }

    fn execute(&mut self, action: &NimAction) -> Result<(), NimError> {
        use NimError::*;
        use TokenState::*;
        // Assert, that the move is legal.
        if self.last_token_taken_by.is_some() {
            Err(GameAlreadyOver)
        } else if action.token_indices.is_empty() {
            Err(NotEnoughtTokens)
        } else if action.token_indices.len() > 3 {
            Err(ToManyTokens)
        } else if action.token_indices.iter().any(|i| *i >= self.tokens.len()) {
            Err(TokenOutOfBounds)
        } else if action
            .token_indices
            .iter()
            .any(|i| self.tokens[*i] == TokenMissing)
        {
            Err(TokenAlreadyMissing)
        } else {
            // Mark tokens as removed.
            action
                .token_indices
                .iter()
                .for_each(|i| self.tokens[*i] = TokenMissing);
            // Check if the game is over.
            if self.tokens.iter().all(|t| *t == TokenMissing) {
                self.last_token_taken_by = Some(self.current_player);
            } else {
                // Proceed to the next player.
                self.current_player += 1;
                if self.current_player == self.player_count {
                    self.current_player = 0;
                }
            }

            Ok(())
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;
    #[test]
    fn take_some_tokens() {
        let mut game = Nim::new(15, 2);
        game.execute(&NimAction::from_vec(vec![2, 4, 6])).unwrap();
        game.execute(&NimAction::from_vec(vec![1, 7])).unwrap();
        game.execute(&NimAction::from_vec(vec![11])).unwrap();
        game.execute(&NimAction::from_vec(vec![13, 3, 5])).unwrap();
        game.execute(&NimAction::from_vec(vec![8, 9])).unwrap();
        game.execute(&NimAction::from_vec(vec![12, 14])).unwrap();
        game.execute(&NimAction::from_vec(vec![0, 10])).unwrap();
        assert_eq!(game.last_token_taken_by, Some(0));
    }

    #[test]
    fn test_double_take() {
        let mut game = Nim::new(15, 2);
        game.execute(&NimAction::from_vec(vec![2, 4, 6])).unwrap();
        let game_clone = game.clone();
        let result = game.execute(&NimAction::from_vec(vec![1, 7, 2]));
        assert_eq!(result, Err(NimError::TokenAlreadyMissing));
        assert_eq!(game_clone, game);
    }
}
