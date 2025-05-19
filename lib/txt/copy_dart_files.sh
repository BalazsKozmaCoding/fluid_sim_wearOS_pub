#!/bin/bash

# Directory containing the .dart files
# Get the directory of the currently executing script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# Determine the workspace root directory (assuming script is in workspace_root/lib/txt)
WORKSPACE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Directory containing the .dart files (relative to workspace root)
SOURCE_DIR="$WORKSPACE_ROOT/lib"
# Directory to copy the files to (relative to workspace root)
DEST_DIR="$WORKSPACE_ROOT/lib/txt"

# Create the destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Find all .dart files in the source directory and its subdirectories and copy them to the destination directory with .txt extension
find "$SOURCE_DIR" -name "*.dart" -print0 | while IFS= read -r -d $'\0' file; do
  echo "Found file: $file" # Debugging line
  # Get the base filename without the source directory path
  # Get the relative path from the source directory
  relative_path="${file#$SOURCE_DIR/}"
  # Remove the .dart extension and add .dart.txt
  new_filename="${relative_path%.dart}.dart.txt"
  echo "New filename: $new_filename" # Debugging line
  # Create necessary subdirectories in the destination
  mkdir -p "$(dirname "$DEST_DIR/$new_filename")"
  echo "Creating directory: $(dirname "$DEST_DIR/$new_filename")" # Debugging line
  # Copy the file
  cp "$file" "$DEST_DIR/$new_filename"
  echo "Copied $file to $DEST_DIR/$new_filename" # Debugging line
done

# Find all .cpp files in the src directory and copy them to the destination directory with .cpp.txt extension
find "$WORKSPACE_ROOT/src" -name "*.cpp" -print0 | while IFS= read -r -d $'\0' file; do
  echo "Found file: $file" # Debugging line
  # Get the base filename without the source directory path
  # Get the relative path from the src directory
  relative_path="${file#$WORKSPACE_ROOT/src/}"
  # Remove the .cpp extension and add .cpp.txt
  new_filename="${relative_path%.cpp}.cpp.txt"
  echo "New filename: $new_filename" # Debugging line
  # Create necessary subdirectories in the destination
  mkdir -p "$(dirname "$DEST_DIR/$new_filename")"
  echo "Creating directory: $(dirname "$DEST_DIR/$new_filename")" # Debugging line
  # Copy the file
  cp "$file" "$DEST_DIR/$new_filename"
  echo "Copied $file to $DEST_DIR/$new_filename" # Debugging line
done

echo "Copied .cpp files from src to $DEST_DIR with .cpp.txt extension."