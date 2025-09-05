# Debug Login

When login fails in this setup, it’s almost always one of these:

- the Secret’s values aren’t what you expect,
- the init Groovy didn’t run (or ran before the Secret existed),
- the user exists but with a different password.

Following are steps to start over or debug and fix the issue.

## Nuclear Reset (For Lab Environments Only!)

If you prefer, fully reset Jenkins and start over.

> [!CAUTION]
> ⚠️ This removes the controller and wipes all data from the Jenkins persistent volume claim.

For a shortcut, run the script [reset.sh](./reset.sh) or apply the following steps one at a time.

1. Delete the deployment and persistent volume claim

    ```bash
    kubectl -n "$NS" delete deploy jenkins-yaml-controller
    kubectl -n "$NS" delete pvc jenkins-yaml-home
    ```

1. Re-create the secret as outlined in the [Setup](../README.md#setup) steps.

1. Apply configurations 04–07 and rollout again.

    ```bash
    kubectl -n "$NS" apply -f ./yaml-config/04-persistent-volume-claim.yaml
    kubectl -n "$NS" apply -f ./yaml-config/05-configmap-init.yaml
    kubectl -n "$NS" apply -f ./yaml-config/06-deployment.yaml
    kubectl -n "$NS" apply -f ./yaml-config/07-service.yaml
    ```

Then forward the port and try logging in as defined in [Connect to the Jenkins Web Interface](../README.md#connect-to-the-jenkins-web-interface).

## Debugging Step by Step

### 1. Verify what Jenkins *thinks* the creds are (from the Secret)

```bash
# See the actual values stored in the Secret
kubectl -n "$NS" get secret jenkins-shared-admin-secret -o jsonpath='{.data.JENKINS_ADMIN_ID}' | base64 -d; echo
kubectl -n "$NS" get secret jenkins-shared-admin-secret -o jsonpath='{.data.JENKINS_ADMIN_PASSWORD}' | base64 -d; echo
```

If either is off, recreate it:

```bash
kubectl -n "$NS" delete secret jenkins-shared-admin-secret --ignore-not-found
kubectl -n "$NS" create secret generic jenkins-shared-admin-secret \
  --from-literal=JENKINS_ADMIN_ID="$JENKINS_ADMIN_ID" \
  --from-literal=JENKINS_ADMIN_PASSWORD="$JENKINS_ADMIN_PASSWORD"
```

### 2. Check that the init script actually landed and security is set

```bash
# Grab the pod name
POD=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=jenkins-yaml -o jsonpath='{.items[0].metadata.name}')

# Is the init script in JENKINS_HOME (the place Jenkins executes from)?
kubectl -n "$NS" exec "$POD" -- ls -l /var/jenkins_home/init.groovy.d || true

# Is security enabled and which realm is configured?
kubectl -n "$NS" exec "$POD" -- awk 'NR<=120' /var/jenkins_home/config.xml | sed -n '1,120p'
```

Quick reads in `config.xml` you want to see:

- `<useSecurity>true</useSecurity>`
- `<securityRealm class="hudson.security.HudsonPrivateSecurityRealm">`
- `<authorizationStrategy class="hudson.security.FullControlOnceLoggedInAuthorizationStrategy">`

Also check if a user directory exists:

```bash
kubectl -n "$NS" exec "$POD" -- ls -l /var/jenkins_home/users || true
```

### 3. Fast, non-destructive fix: force-(re)create or reset the admin user

If the user exists but the password is wrong, or if the init didn’t run when the Secret was ready, drop a **one-time reset script** directly into `$JENKINS_HOME/init.groovy.d` and restart. It uses the same env vars from the Secret.

```bash
# Write a force-reset script into JENKINS_HOME
kubectl -n "$NS" exec -i "$POD" -- bash -lc 'cat > /var/jenkins_home/init.groovy.d/20-reset-admin.groovy <<''EOF''
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstanceOrNull()
if (instance == null) return

def userId = System.getenv("JENKINS_ADMIN_ID") ?: "admin"
def pass  = System.getenv("JENKINS_ADMIN_PASSWORD") ?: "admin"

// Ensure a local user realm
def realm = instance.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
  realm = new HudsonPrivateSecurityRealm(false)
}

// Create or reset the admin account
def u = hudson.model.User.getById(userId, false)
if (u == null) {
  realm.createAccount(userId, pass)
} else {
  u.addProperty(new HudsonPrivateSecurityRealm.Details(pass))
  u.save()
}

instance.setSecurityRealm(realm)

// Lock down to logged-in users
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
println("✅ Admin user \'" + userId + "\' ensured/updated.")
EOF'
'

# Restart the controller so the script runs on startup
kubectl -n "$NS" rollout restart deployment/jenkins-yaml-controller
kubectl -n "$NS" rollout status deployment/jenkins-yaml-controller
```

Now try logging in again with `$JENKINS_USER` / `$JENKINS_PASS`.

After it works, you can delete that file if you want:

```bash
kubectl -n "$NS" exec "$POD" -- rm -f /var/jenkins_home/init.groovy.d/20-reset-admin.groovy
```
