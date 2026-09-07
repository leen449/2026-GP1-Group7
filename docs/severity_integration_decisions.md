# Severity integration decisions

## Current deployment: Experiment 10

CrashLens now deploys `severity_resnet50_ordinal_csp650_v1.pth`. This is the
CSP650 full-image ResNet50 trained with a two-logit ordinal head. The model
receives the complete image, resized to 224x224, converted to RGB, and
normalized with the ImageNet mean `[0.485, 0.456, 0.406]` and standard
deviation `[0.229, 0.224, 0.225]`.

The two outputs are independent threshold logits:

- `greaterThanMinor`: sigmoid(logit 1), meaning the probability that severity
  is above Minor.
- `greaterThanModerate`: sigmoid(logit 2), meaning the probability that
  severity is above Moderate.

The fixed 0.5 rule is used without softmax or argmax:

- `p_gt_minor < 0.5` -> `minor`
- otherwise, `p_gt_moderate < 0.5` -> `moderate`
- otherwise -> `severe`

The backend writes the stable `severity` strings used by the rest of the
application. It also writes `ordinalProbabilities` with the two threshold
probabilities. `severityConfidence` remains for backward Firestore schema
compatibility, but it is now an **ordinal decision confidence**, not a softmax
class probability. It is calculated from the selected ordinal decision and
must not be compared with `costConfidence`.

The severity model runs on the same full image already downloaded for YOLO.
The existing pipeline remains unchanged: damage detection, full-image severity,
part segmentation, and cost estimation. If YOLO finds no damage, severity is
skipped. If severity inference fails, detection results are retained.

`overallSeverity` remains the worst image-level severity according to the
existing Minor < Moderate < Severe ranking. Reports, Flutter screens, and cost
estimation continue to consume these existing severity strings. The existing
severity factors remain Minor=0.85, Moderate=1.00, and Severe=1.25.

## Rollback model

The former `severity_resnet50.pth` file is retained in `backend_api/weight/`
for rollback. It is a three-class softmax model and must not be loaded by the
current ordinal service. Its old softmax confidence semantics are obsolete for
the current deployment.

Historical experiment details should be kept with the model artifacts. Any
future replacement must document its head shape, preprocessing, decoding rule,
and Firestore compatibility before deployment.
