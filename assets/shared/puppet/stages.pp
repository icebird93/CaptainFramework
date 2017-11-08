# Stages: first -> main -> last
stage { 'first':
	before => Stage['main'],
}
stage { 'last': }
Stage['main'] -> Stage['last']