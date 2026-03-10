use crate::StarterId;

/// Slot state machine
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SlotState {
    Empty,
    Occupied(StarterId),
    Locked(StarterId), // During invitation
}

/// Slot manager for capsule's 5 slots
#[derive(Debug, Clone)]
pub struct SlotManager {
    slots: [SlotState; 5],
}

impl SlotManager {
    pub fn new() -> Self {
        Self {
            slots: [
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
            ],
        }
    }

    pub fn get_state(&self, index: usize) -> Option<&SlotState> {
        self.slots.get(index)
    }

    pub fn occupy_slot(&mut self, index: usize, starter_id: StarterId) -> Result<(), &'static str> {
        if index >= 5 {
            return Err("Invalid slot index");
        }
        
        match self.slots[index] {
            SlotState::Empty => {
                self.slots[index] = SlotState::Occupied(starter_id);
                Ok(())
            }
            _ => Err("Slot is not empty"),
        }
    }

    pub fn lock_slot(&mut self, index: usize) -> Result<(), &'static str> {
        if index >= 5 {
            return Err("Invalid slot index");
        }
        
        match self.slots[index] {
            SlotState::Occupied(starter_id) => {
                self.slots[index] = SlotState::Locked(starter_id);
                Ok(())
            }
            _ => Err("Cannot lock empty slot"),
        }
    }

    pub fn unlock_slot(&mut self, index: usize) -> Result<(), &'static str> {
        if index >= 5 {
            return Err("Invalid slot index");
        }
        
        match self.slots[index] {
            SlotState::Locked(starter_id) => {
                self.slots[index] = SlotState::Occupied(starter_id);
                Ok(())
            }
            _ => Err("Slot is not locked"),
        }
    }

    pub fn free_slot(&mut self, index: usize) -> Result<(), &'static str> {
        if index >= 5 {
            return Err("Invalid slot index");
        }
        
        match self.slots[index] {
            SlotState::Occupied(_) | SlotState::Locked(_) => {
                self.slots[index] = SlotState::Empty;
                Ok(())
            }
            _ => Err("Slot is already empty"),
        }
    }

    pub fn find_empty_slot(&self) -> Option<usize> {
        self.slots.iter().position(|s| matches!(s, SlotState::Empty))
    }

    pub fn find_slot_by_starter(&self, starter_id: StarterId) -> Option<usize> {
        self.slots.iter().position(|s| match s {
            SlotState::Occupied(id) | SlotState::Locked(id) => *id == starter_id,
            _ => false,
        })
    }

    pub fn is_locked(&self, index: usize) -> bool {
        matches!(self.slots.get(index), Some(SlotState::Locked(_)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::primitives::StarterId;

    #[test]
    fn test_slot_manager() {
        let mut manager = SlotManager::new();
        let starter_id = StarterId::new([1u8; 32]);
        
        assert_eq!(manager.find_empty_slot(), Some(0));
        
        // Occupy slot 0
        assert!(manager.occupy_slot(0, starter_id).is_ok());
        assert_eq!(manager.find_empty_slot(), Some(1));
        
        // Lock slot 0
        assert!(manager.lock_slot(0).is_ok());
        assert!(manager.is_locked(0));
        
        // Find by starter
        assert_eq!(manager.find_slot_by_starter(starter_id), Some(0));
        
        // Unlock
        assert!(manager.unlock_slot(0).is_ok());
        assert!(!manager.is_locked(0));
        
        // Free
        assert!(manager.free_slot(0).is_ok());
        assert_eq!(manager.find_empty_slot(), Some(0));
    }
}
