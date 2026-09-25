import os
import pickle
import tarfile

root = "./data"
archive = os.path.join(root, "cifar-100-python.tar.gz")
with tarfile.open(archive, "r:gz") as tar:
    raw_file = tar.extractfile("cifar-100-python/test")
    raw = pickle.load(raw_file, encoding="latin1")

people = next(i for i, label in enumerate(raw["coarse_labels"]) if label == 14)
nonhuman = next(i for i, label in enumerate(raw["coarse_labels"]) if label != 14)

def write_frame(index, filename):
    # CIFAR stores each image as 3072 bytes: R plane, G plane, B plane.
    image = raw["data"][index]
    with open(filename, "w", newline="\n") as f:
        for y in range(32):
            for x in range(32):
                r = image[y * 32 + x]
                g = image[1024 + y * 32 + x]
                b = image[2048 + y * 32 + x]
                f.write(f"{int(r):02X}{int(g):02X}{int(b):02X}\n")
    print(f"Wrote {filename} (1024 RGB pixels)")

write_frame(people, "human_frame.mem")
write_frame(nonhuman, "nonhuman_frame.mem")
