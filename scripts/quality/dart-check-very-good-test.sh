#!/bin/bash

checkCommand() {
  # Deactivate only if installed
  if dart pub global list | grep -q "very_good_cli"; then
    echo "very_good_cli already installed — deactivating..."
    dart pub global deactivate very_good_cli

    if [ $? -ne 0 ]; then
      echo "❌ Failed to deactivate very_good_cli"
      return 1
    fi
  fi

  # Install fresh
  echo "Installing very_good_cli..."
  if dart pub global activate very_good_cli; then
    echo "Activation successful"
    return 0
  else
    echo "❌ Activation failed"
    return 1
  fi
}

checkCommand