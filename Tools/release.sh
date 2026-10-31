#!/bin/zsh
# Releases the server and the app together, server first, so a TestFlight build never depends on
# server code that isn't live yet (the app also hides features the server doesn't list in GET /meta).
#
#   Tools/release.sh            validate the server, deploy it (asks first), bump the build, upload to TestFlight
#   Tools/release.sh --app-only skip the server (nothing changed there)
#
# Needs: the sf CLI signed in to the "prod" org, and the Salesforce project at ../Portal-customerClaims
# (override with PORTAL_DIR). Uploads use the App Store Connect API key in
# ~/.appstoreconnect/aaga-claims.env (ASC_KEY_ID, ASC_ISSUER_ID; the .p8 in ~/.appstoreconnect/private_keys,
# Admin role for cloud signing). Without it, Xcode's signed-in Apple ID for team 62Z8PRAHTS is used.
set -euo pipefail

IOS_DIR=${0:A:h:h}
PORTAL_DIR=${PORTAL_DIR:-$IOS_DIR/../Portal-customerClaims}
ORG=${ORG:-prod}
CLASSES=$PORTAL_DIR/force-app/main/default/classes
TRIGGERS=$PORTAL_DIR/force-app/main/default/triggers

# The mobile API: its classes, triggers and labels, and the tests that cover them.
SOURCES=(
  $CLASSES/PortalApiV1.cls $CLASSES/PortalActivityService.cls $CLASSES/PortalPushService.cls
  $CLASSES/PortalClaimActionsService.cls $CLASSES/PortalLeadActionsService.cls $CLASSES/PortalNewClaimService.cls
  $CLASSES/PortalPeopleService.cls $CLASSES/PortalRecordAccess.cls $CLASSES/ClaimRecordBannerController.cls
  $CLASSES/CustomerRelatedClaimsController.cls $CLASSES/UserRelatedProspectsController.cls
  $CLASSES/PortalApiV1Test.cls $CLASSES/PortalActivityServiceTest.cls $CLASSES/PortalPushServiceTest.cls
  $CLASSES/PortalClaimActionsServiceTest.cls $CLASSES/PortalLeadActionsServiceTest.cls $CLASSES/PortalNewClaimServiceTest.cls
  $CLASSES/PortalPeopleServiceTest.cls $CLASSES/CustomerRelatedClaimsControllerTest.cls $CLASSES/UserRelatedProspectsControllerTest.cls
  $TRIGGERS/PortalPushExternalComment.trigger $TRIGGERS/PortalPushPayment.trigger $TRIGGERS/PortalPushTask.trigger
  $TRIGGERS/PortalPushFeedItem.trigger $TRIGGERS/PortalPushFeedComment.trigger
  $TRIGGERS/PortalPushCase.trigger $TRIGGERS/PortalPushCaseComment.trigger $TRIGGERS/PortalPushSignature.trigger
  $CLASSES/PortalMyCasesController.cls $CLASSES/PortalCaseDetailController.cls $CLASSES/PortalCaseControllersTest.cls
  $CLASSES/MobileAppMonitor.cls $CLASSES/MobileAppMonitorTest.cls $CLASSES/PortalMobileAppAccess.cls $CLASSES/PortalMobileAppAccessTest.cls
  $CLASSES/PortalAccountService.cls $CLASSES/PortalAccountServiceTest.cls $CLASSES/PortalFilesTest.cls
  $TRIGGERS/MobileAppErrorEvents.trigger $TRIGGERS/PortalMobileAppAccess.trigger
  $PORTAL_DIR/force-app/main/default/objects/Mobile_App_Log__c $PORTAL_DIR/force-app/main/default/objects/Mobile_App_Error__e
  $PORTAL_DIR/force-app/main/default/tabs/Mobile_App_Log__c.tab-meta.xml
  $PORTAL_DIR/force-app/main/default/permissionsets/Mobile_App_Monitoring.permissionset-meta.xml
  $PORTAL_DIR/force-app/main/default/labels
)
TESTS=(PortalApiV1Test PortalActivityServiceTest PortalPushServiceTest PortalClaimActionsServiceTest PortalLeadActionsServiceTest
       PortalNewClaimServiceTest PortalPeopleServiceTest CustomerRelatedClaimsControllerTest UserRelatedProspectsControllerTest
       ClaimRecordBannerControllerTest PortalRecordAccessTest MobileAppMonitorTest PortalMobileAppAccessTest
       PortalAccountServiceTest PortalFilesTest PortalCaseControllersTest SignatureFlowTest)

source_args=()
for s in $SOURCES; do source_args+=(--source-dir "$s"); done
test_args=()
for t in $TESTS; do test_args+=(--tests "$t"); done

if [[ ${1:-} != --app-only ]]; then
  echo "▶ Validating the server against $ORG…"
  (cd "$PORTAL_DIR" && sf project deploy validate -o "$ORG" $source_args --test-level RunSpecifiedTests $test_args --wait 40)
  read "answer?Deploy the server to $ORG now? [y/N] "
  [[ $answer == [yY]* ]] || { echo "Stopped before deploying. Nothing was uploaded."; exit 1; }
  (cd "$PORTAL_DIR" && sf project deploy start -o "$ORG" $source_args --test-level RunSpecifiedTests $test_args --wait 40)
fi

echo "▶ Bumping the build number…"
cd "$IOS_DIR"
PBX=AAGAClaims.xcodeproj/project.pbxproj
build=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' $PBX | grep -o '[0-9]*$')
next=$((build + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = $build;/CURRENT_PROJECT_VERSION = $next;/g" $PBX
version=$(grep -m1 -o 'MARKETING_VERSION = [0-9.]*' $PBX | grep -o '[0-9.]*$')
echo "  $version ($next)"
grep -q "version: \"$version\"" AAGAClaims/Features/Account/WhatsNew.swift \
  || echo "  ⚠️  No release notes for $version in WhatsNew.swift. Users will see none for this version."

echo "▶ Archiving and uploading to TestFlight…"
auth_args=()
ASC_ENV=~/.appstoreconnect/aaga-claims.env
if [[ -f $ASC_ENV ]]; then
  source $ASC_ENV
  auth_args=(-authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
             -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID)
fi
OUT=$(mktemp -d)
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
xcodebuild archive -project AAGAClaims.xcodeproj -scheme AAGAClaims -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/AAGAClaims.xcarchive" \
  -clonedSourcePackagesDirPath .build/spm -allowProvisioningUpdates $auth_args DEVELOPMENT_TEAM=62Z8PRAHTS -quiet
xcodebuild -exportArchive -archivePath "$OUT/AAGAClaims.xcarchive" -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates $auth_args -quiet
rm -rf "$OUT"

git commit -qam "Build $next for TestFlight"
echo "✔ $version ($next) uploaded. TestFlight shows it in about 5–15 minutes."
