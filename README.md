## For details of DAJIN, please visit the original DAJIN github page.
https://github.com/akikuno/DAJIN

## EZ-DAJIN
EZ-DAJIN is a Docker image of DAJIN. No need any installation except for Docker or Singularity. This is a ready-to-use version of DAJIN. All the test was done at NIG (National Institute of Genetics) Supercomputer, Japan.

## Citation
PLOS BIOLOGY

@article{Kuno_2022,
	title={DAJIN enables multiplex genotyping to simultaneously validate intended and unintended target genome editing outcomes},
	volume={20},
	url={https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001507},
	DOI={10.1371/journal.pbio.3001507},
	number={1},
	journal={PLOS Biology},
	author={Kuno, Akihiro and Ikeda, Yoshihisa and Ayabe, Shinya and Kato, Kanako and Sakamoto, Kotaro and Suzuki, Sayaka R. and Morimoto, Kento and Wakimoto, Arata and Mikami, Natsuki and Ishida, Miyuki and et al.},
	year={2022},
	month={Jan},
	pages={e3001507}
}

## License
The original DAJIN is under the MIT License - see the LICENSE file for details. EZ-DAJIN follows the same lisense.

## Intallation
Make you own docker image from dockerfile or use the docker image on Docker hub.
```
docker pull geedrn/dajin:tensorflow
```

## Run your analysis
The code below uses the test data in the original DAJIN. Change the design.txt accordingly for your customized analysis.
```
# For Docker people
docker run -it --rm -v $(pwd):/data -t geedrn/dajin:tensorflow /bin/bash
git clone https://github.com/akikuno/DAJIN.git
./DAJIN/DAJIN -i DAJIN/example/design.txt
# For Singularity people
singularity exec dajin_tensorflow.sif /bin/bash -c 'source activate; ./DAJIN/DAJIN -i ./DAJIN/DAJIN/example/design.txt'
```



