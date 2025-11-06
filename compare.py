import numpy as np
import matplotlib.pyplot as plt
import argparse

def extract_filtered_output(filepath):
    """
    Extracts the list of space-separated floating-point numbers from the line
    starting with "Filtered output:".

    Args:
        filepath (str): The path to the text file.

    Returns:
        list: A list of floats found on the line. Returns an empty list
              if the line is not found or no numbers are on it.
    """
    extracted_values = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                # Check if the line starts with the target string (stripping whitespace)
                if line.strip().startswith("Filtered output:"):
                    # Split the line at the first colon
                    # parts[1] will be " 1.0 2.0 3.0 ... 10.0\n"
                    parts = line.split(":", 1)
                    
                    if len(parts) == 2:
                        # Strip leading/trailing whitespace (like the leading space and newline)
                        # This gives: "1.0 2.0 3.0 ... 10.0"
                        number_string = parts[1].strip()
                        
                        # Split the string by whitespace to get individual numbers
                        # This gives: ['1.0', '2.0', '3.0', ..., '10.0']
                        number_list_str = number_string.split()
                        
                        # Convert each number string to a float
                        try:
                            extracted_values = [float(num) for num in number_list_str]
                            # Found what we came for, no need to read the rest of the file
                            return extracted_values
                        except ValueError as e:
                            # Handle cases where a value on the line isn't a valid number
                            print(f"Error converting number to float: {e}")
                            return []
                            
    except FileNotFoundError:
        print(f"Error: The file '{filepath}' was not found.")
    except Exception as e:
        print(f"An error occurred: {e}")
        
    # Return an empty list if the line was never found
    return extracted_values

def read_signal(path):
    with open(path, "r") as f:
        return np.array(list(map(float, f.readlines()[0].split())))
    
parser = argparse.ArgumentParser(description="Barebones Wiener filter (pure Python)")
parser.add_argument("--input", default="input.txt")
parser.add_argument("--desired", default="desired.txt")
parser.add_argument("--order", type=int, default=10)
parser.add_argument("--output", default="output.txt")
args = parser.parse_args()

desired = read_signal(args.desired)
wiener_output = extract_filtered_output(args.output)
input_signal = read_signal(args.input)

# plt.plot(input_signal, color = "b", linestyle = "dashed", label = "Input values")
plt.plot(desired, color = "r", linestyle = "solid", label = "Desired values")
plt.plot(wiener_output, color = "g", linestyle = "solid", label = "Output")

plt.legend()
plt.show()