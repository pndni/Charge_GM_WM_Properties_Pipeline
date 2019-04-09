import nibabel
import numpy as np
import sys


if __name__ == '__main__':
    x = np.asanyarray(nibabel.load(sys.argv[1]).dataobj)
    u = np.unique(x)
    nl = len(u)
    if 0 in u:
        nl -= 1
    print(nl)
