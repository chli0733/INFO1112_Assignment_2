import sys
import matplotlib
matplotlib.use("Agg")                      # no screen in the container, draw straight to a file
import matplotlib.pyplot as plt
 
data_file, png_file = sys.argv[1], sys.argv[2]
 
years, pops = [], []
with open(data_file) as f:                 # each line is "year,population" (made by awk in server.sh)
    for line in f:
        year, pop = line.strip().split(",")
        years.append(int(year))
        pops.append(int(pop))
 
plt.figure(figsize=(8, 5))
plt.plot(years, pops, marker="o", label="NSW")
plt.title("NSW estimated resident population")
plt.xlabel("Year")
plt.ylabel("Population")
plt.xticks(years)
plt.ticklabel_format(axis="y", style="plain")   # full numbers, not 8.5e6
plt.legend()
plt.tight_layout()
plt.savefig(png_file)