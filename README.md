# CircleCI and Cypress Workshop

## Prerequisites

- Knowledge of Git version control system  
- Accounts for services we will be using  
  - GitHub account - where the code is hosted
  - CircleCI - cloud-based CI/CD
  - Terraform - Infrastructure as Code (IaS) provider to deploy infrastructure
  - Snyk - developer security platform
  - Docker Hub - container registry to host custom images
- A code editor - Visual Studio Code is preferred but you can use anything

## Chapter 0 - The Prologue and Prep

Fork this project! You will need a GitHub account.

This project can run on your machine if you have the correct dependencies installed (Git, Terraform, DigitalOcean CLI, Node.js, and Cypress)

The commands used here are mostly using Bash, Git, and Python 3 - make sure they are installed and available. If using Windows, the commands might be different than the ones listed here.

Copy over the credentials source file. This is untracked in Git and will be used by a script to populate your CircleCI secret variables.

```
cp scripts/util/credentials.sample.toml credentials.toml
```

### IMPORTANT! Sign up for the required services and prepare credentials

If you don't do this, you'll have a bad time.

#### Make a Credentials `.toml` file

We will be filling out the credentials file before we start working with our CircleCI project.

- Rename `credentials.sample.toml` to `credentials.toml`
#### Digital Ocean

You do not need your own Digital Ocean account, nor do you need to log into Digital Ocean.

- We will give each of you a unique API Token during the workshop.
- Copy the token string to `credentials.toml` - `digitalocean_token`

#### Terraform Cloud

We will use Terraform to provision our infrastructure on Digital Ocean.

- Create an account with Hashicorp Terraform - https://app.terraform.io/
- Go to your user settings by clicking on your avatar (top left), and select "User Settings"
- From there, click on "Tokens"
- Create an API token
- Copy the token string to `credentials.toml` - `tf_cloud_key`

#### Docker Hub

- Create an account with Docker Hub - https://hub.docker.com/ We will use Docker Hub as a repository for our app images.
- Go to "Account Settings" (top right), and select Security
- Create New Access Token
- copy your username to `credentials.toml` - `docker_username`
- copy your token string to `credentials.toml` - `docker_token`

#### Snyk

- Create an account with Snyk - https://app.snyk.io/ - We will use Snyk to run an automated security scan of our application an its dependencies.
- Skip the integration step by clicking "Choose other integration" at the bottom of the options list.
- Click on your avatar in the bottom of the sidebar to show a dropdown
- Choose "Account Settings"
- Click to show your Auth Token
- Copy the auth token string to `credentials.toml` - `snyk_token`

### How this workshop works

We will go from chapter to chapter - depending on people's backgrounds we might go faster or slower.

To jump between chapters we have prepared a set of handy scripts you can run in your terminal, which will set up your environment so you can follow along.

The chapters will copy and overwrite certain files in your workspace, so after running each script, commit the changes and push it, which will run it on CircleCI.

The scripts to run are:

`./scripts/do_1_start.sh` - Beginning of first stage
`./scripts/do_2.sh` - End of first stage/Start of second stage
`./scripts/do_3.sh` - End of second stage/Start of third stage
`./scripts/do_4.sh` - Final state

### Overview of the project

The project is a simple web application based on the [Vitesse template](https://github.com/antfu/vitesse). We've packaged it in a Docker container, and deployed it on Kubernetes - hosted on DigitalOcean infrastructure.
We also have some tests, a security scan, a step to build the image, a provisioning step for DigitalOcean, and finally a deploy step.

### Workshop topics covered

#### Stage 1 - Basics of CI

- YAML
- Reviewing the first pipeline
- Running tests and checks in parallel
- Reporting test results
- Caching dependencies
- Using the orb to install and cache dependencies
- Setting up secrets and contexts
- Building and pushing a Docker image
- Scanning vulnerabilities

#### Stage 2 - Deployments and infrastructure provisioning

- Cloud native principles
- Provision infrastructure with Terraform on DigitalOcean
- Deploy to infrastructure
- Run a smoke test on deployed app
- Destroy the deployed application and provisioned test infrastructure

#### Chapter 3 - Advanced CircleCI concepts

- Filtering pipelines on branches and tags
- Approval production deployment
- Provisioning both test and production infrastructure and deployment

## Chapter 1 - Basics of CircleCI

Most of our work will be in `./circleci/config.yml` - the CircleCI configuration file. This is where we will be describing our CI/CD pipelines.
This workshop is written in chapters, so you can jump between them by running scripts in `scripts/` dir, if you get lost and want to catch up with something.
To begin, prepare your environment for the initial state by running the start script: `./scripts/do_1_start.sh`

Go to app.circleci.com, and if you haven't yet, log in with your GitHub account (or create a new one).
Navigate to the `Projects` tab, and find this workshop project there - `cicd-workshop`.

We will start off with a basic continuous integration pipeline, which will run your tests each time you commit some code. Run a commit for each instruction. The first pipeline is already configured, if it's not you can run: `./scripts/do_0_start.sh` to create the environment.

Now review the `.circleci/config.yaml` find the `jobs` section, and a job called `build`, and workflow called `build_test_deploy`:

```yaml
version: 2.1

jobs:
  build:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - run:
          command: |
            npm install
      - run:
          command: |
            npm run lint
            npm run test-ci
            npm run build

workflows:
  build_test_deploy:
    jobs:
      - build

```

Original configuration has multiple commands in a single job. That is not ideal as any one of these can fail and we won't quickly know where it failed. We can split across multiple commands:

```yaml
jobs:
  build:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - run:
          command: |
            npm install
      - run:
          command: |
            npm run lint
      - run:
          command: |
            npm run test-ci
      - run:
          command: |
            npm run build
```

That way we have a nicer overview of the steps, but we can split them further, by splitting testing and linting into parallel jobs instead. We need to define the jobs and their steps, and add them to the workflow:

```yaml
jobs:
  build:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - run:
          command: |
            npm install
      - run:
          command: |
            npm run build

  test:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - run:
          command: |
            npm install
      - run:
          command: |
            npm run test-ci

  lint:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - run:
          command: |
            npm install
      - run:
          command: |
            npm run lint

workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
```

- Now we can shave off some time by caching our dependencies so they don't get downloaded each time. Create a command `install_and_cache_node_dependencies` and use it instead of the usual `npm install` command in the jobs:

```yaml
commands:
  install_and_cache_node_dependencies:
    steps:
      - restore_cache:
            keys:
              - v2-deps-{{ checksum "package-lock.json" }}
              - v2-deps-
      - run:
          name: Install deps
          command: npm install
      - save_cache:
          key: v1-deps-{{ checksum "package-lock.json" }}
          paths:
              - node_modules

jobs:
  build:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - install_and_cache_node_dependencies
      - run:
          command: |
            npm run build

  test:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - install_and_cache_node_dependencies
      - run:
          command: |
            npm run test-ci

  lint:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - install_and_cache_node_dependencies
      - run:
          command: |
            npm run lint

```

### Introducing orbs

- Simplify this further by introducing the Node.js orb which contains this logic already implemented and ready to use, so we don't have to use the command we created earlier:

```yaml
orbs:
  node: circleci/node@5.0.3

jobs:
  build:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - node/install-packages
      - run:
          command: |
            npm run build

  test:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - node/install-packages
      - run:
          command: |
            npm run test-ci

  lint:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - node/install-packages
      - run:
          command: |
            npm run lint

```

Now we have three parallel jobs that cache dependencies and execute extremely quickly, and independently of each other.

### Test reporting

- Report test results to CircleCI. Change the test job to `test-ci-reporting`, which is configured to export our test results in JUnit format that CircleCI can understand.

```json
{
  ...
  "scripts":
  {
    ...
    "test-ci-reporting": "vitest run --reporter=junit --outputFile output/results.xml",
    ...
  }
  ...
}
```

- Add Change the `test` job to use this command and add the following commands to it:

```yaml
jobs:
  build_and_test:
    ...
      - run:
          name: Run tests
          command: npm run test-ci-reporting
      - run:
          name: Copy tests results for storing
          command: |
            mkdir test-results/
            cp test-results.xml test-results/
          when: always
      - store_test_results:
          path: test-results
      - store_artifacts:
          path: test-results
```

You might also notice that you can add names to run steps so that they show up nicer in the dashboard.

### Secrets and Contexts

CircleCI lets you store secrets safely on the platform where they will be encrypted and only made available to the executors as environment variables. The first secrets you will need are credentials for Docker Hub which you'll use to deploy your image to Docker Hub.

We have prepared a script for you to create a context and set it up with all the secrets you will need in CircleCI. This will use the CircleCI API.

You should have all the required accounts for third party services already, and are just missing the CircleCI API token and the organization ID:

- In app.circleci.com click on your user image (bottom left)
- Go to Personal API Tokens
- Generate new API token and insert it `credentials.toml`
- In app.circleci.com click on the Organization settings.
- Copy the Organization ID value and insert it in `credentials.toml`

Make sure that you have all the required service variables set in `credentials.toml`, and then run the script (but make sure you have the toml dependency)

```bash
cp scripts/util/credentials.sample.toml credentials.toml
pip3 install toml
python3 scripts/prepare_contexts.py
```

Most of the things you do in CircleCI web interface can also be done with the API. You can inspect the newly created context and secrets by going to your organization settings. Now we can create a new job to build and deploy a Docker image.

### Building and deploying a Docker image

- First introduce the Docker orb:

```yaml
orbs:
  node: circleci/node@5.0.2
  docker: circleci/docker@2.1.4
```

- Add a new job:

```yaml
jobs:
...
build_docker_image:
  docker:
    - image: cimg/base:stable
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: false
    - docker/check
    - docker/build:
        image: $DOCKER_LOGIN/$CIRCLE_PROJECT_REPONAME
        tag: 0.1.<< pipeline.number >>
    - docker/push:
        image: $DOCKER_LOGIN/$CIRCLE_PROJECT_REPONAME
        tag: 0.1.<< pipeline.number >>
```

In the workflow, add the new job:

```yaml
workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
        - build_docker_image

```

This doesn't run unfortunately - our `build_docker_image` doesn't have the required credentials.
Add the context we created earlier:

```yaml
workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
        - build_docker_image:
            context:
              - cicd-workshop
```

This will now build and push your Docker image to Docker hub. Last thing to do in this chapter is to set up automated security scanning tool.

### Integrate automated dependency vulnerability scan

- First let's integrate a security scanning tool in our process. We will use Snyk, for which you should already have the account created and environment variable set.

- Add Snyk orb:

```yaml
orbs:
  node: circleci/node@5.0.3
  docker: circleci/docker@2.1.4
  snyk: snyk/snyk@1.4.0
```

Note: if you push this, you are likely to see the pipeline fail. This is because the Snyk orb comes from a third-party, developed by Snyk themselves. This is a security feature that you can overcome by opting in to partner and community orbs in your organisation settings - security.

- Add dependency vulnerability scan job:

```yaml
jobs:
...
dependency_vulnerability_scan:
  docker:
    - image: cimg/node:16.16.0
  steps:
    - checkout
    - node/install-packages
    - snyk/scan:
        fail-on-issues: true
        monitor-on-build: false
```

- Add the job to workflow. Don't forget to give it the context!:

```yaml
workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
        - build_docker_image:
            context:
              - cicd-workshop
        - dependency_vulnerability_scan:
            context:
              - cicd-workshop
```

- This will now run the automated security scan for your dependencies and fail your job if any of them have known vulnerabilities. Now let's add the security scan to our Docker image build job as well:

```yaml
build_docker_image:
  docker:
    - image: cimg/base:stable
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: false
    - docker/check
    - docker/build:
        image: $DOCKER_LOGIN/$CIRCLE_PROJECT_REPONAME
        tag: 0.1.<< pipeline.number >>
    - snyk/scan:
        fail-on-issues: false
        monitor-on-build: false
        target-file: Dockerfile
        docker-image-name: $DOCKER_LOGIN/$CIRCLE_PROJECT_REPONAME:0.1.<< pipeline.number >>
        project: ${CIRCLE_PROJECT_REPONAME}/${CIRCLE_BRANCH}-app
    - docker/push:
        image: $DOCKER_LOGIN/$CIRCLE_PROJECT_REPONAME
        tag: 0.1.<< pipeline.number >>
```

🎉 Congratulations, you've completed the first part of the exercise!

## Chapter 2 - Infrastructure and deployments

In this section you will learn about cloud native paradigms, infrastructure provisioning, and deployment of infrastructure! We'll also run some tests!

If you got lost in the previous chapter, the initial state of the configuration is in `scripts/configs/config_2.yml`. You can restore it by running `./scripts/chapter_2.sh`.

### Cloud Native deployments

We often use CI/CD pipelines to create our infrastructure, not just run our applications. In the following steps we will be doing just that.

First make sure you have all the credentials created and set in your `cicd-workshop` context:
- DIGITALOCEAN_TOKEN
- TF_CLOUD_KEY

This tells a cloud provider - in our case Digitalocean - what to create for us, so we can deploy our application. We will use a tool called Terraform for it.

- Add the orb for Terraform

```yaml
orbs:
  node: circleci/node@5.0.3
  docker: circleci/docker@2.1.4
  snyk: snyk/snyk@1.4.0
  terraform: circleci/terraform@3.2.0
```

- Add a command to install the Digitalocean CLI - `doctl`. This will be reusable in all jobs across the entire pipeline:

```yaml
commands:
  install_doctl:
    parameters:
      version:
        default: 1.79.0
        type: string
    steps:
      - run:
          name: Install doctl client
          command: |
            cd ~
            wget https://github.com/digitalocean/doctl/releases/download/v<<parameters.version>>/doctl-<<parameters.version>>-linux-amd64.tar.gz
            tar xf ~/doctl-<<parameters.version>>-linux-amd64.tar.gz
            sudo mv ~/doctl /usr/local/bin
```

- In app.terraform.io create a new organization, and give it a name. Create a new workspace called `cicd-workshop-do`.
In the workspace GUI, go to `Settings`, and make sure to switch the `Execution Mode` to `Local`.

- In the file `terraform/do_create_k8s/main.tf` locate the `backend "remote"` section and make sure to change the name to your organization:

```go
  backend "remote" {
    organization = "your_cicd_workshop_org"
    workspaces {
      name = "cicd-workshop-do"
    }
  }
```

Add a job to create a Terraform cluster

```yaml
create_do_k8s_cluster:
    docker:
      - image: cimg/node:16.16.0
    steps:
      - checkout
      - install_doctl:
          version: 1.78.0
      - run:
          name: Create .terraformrc file locally
          command: echo "credentials \"app.terraform.io\" {token = \"$TF_CLOUD_KEY\"}" > $HOME/.terraformrc
      - terraform/install:
          terraform_version: 1.0.6
          arch: amd64
          os: linux
      - terraform/init:
          path: ./terraform/do_create_k8s
      - run:
          name: Create K8s Cluster on DigitalOcean
          command: |
            export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}
            export DO_K8S_SLUG_VER="$(doctl kubernetes options versions \
              -o json -t $DIGITALOCEAN_TOKEN | jq -r '.[0] | .slug')"

            terraform -chdir=./terraform/do_create_k8s apply \
              -var do_token=$DIGITALOCEAN_TOKEN \
              -var cluster_name=$CLUSTER_NAME \
              -var do_k8s_slug_ver=$DO_K8S_SLUG_VER \
              -auto-approve
```

Add the new job to the workflow. Add `requires` statements to only start deployment when all prior steps have completed

```yaml
workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
        - build_docker_image:
            context:
              - cicd-workshop
        - dependency_vulnerability_scan:
            context:
              - cicd-workshop
        - create_do_k8s_cluster:
            context: cicd-workshop
            requires:
              - build
              - test
              - lint
              - build_docker_image
              - dependency_vulnerability_scan

```

### Deploying to your Kubernetes cluster

Now that you have provisioned your infrastructure - a Kubernetes cluster on Digitalocean. It's time to deploy the application to this cluster.

- In app.terraform.io create a new workspace called `deploy-cicd-workshop-do`.
In the workspace GUI, go to `Settings`, and make sure to switch the `Execution Mode` to `Local`. You should now have two workspaces. One holds the infrastructure definitions, and one for deployments.

- In the file `terraform/do_k8s_deploy_app/main.tf` locate the `backend "remote"` section and make sure to change the name to your organization:

```go
  backend "remote" {
    organization = "your_cicd_workshop_org"
    workspaces {
      name = "cicd-workshop-do"
    }
  }
```

Add a job `deploy_to_k8s` which will perform the deployment:

```yaml
deploy_to_k8s:
  docker:
    - image: cimg/node:14.16.0
  steps:
    - checkout
    - install_doctl:
        version: 1.78.0
    - run:
        name: Create .terraformrc file locally
        command: echo "credentials \"app.terraform.io\" {token = \"$TF_CLOUD_KEY\"}" > $HOME/.terraformrc
    - terraform/install:
        terraform_version: 1.0.6
        arch: amd64
        os: linux
    - terraform/init:
        path: ./terraform/do_k8s_deploy_app
    - run:
        name: Deploy Application to K8s on DigitalOcean
        command: |
          export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}
          export TAG=0.1.<< pipeline.number >>
          export DOCKER_IMAGE="${DOCKER_LOGIN}/${CIRCLE_PROJECT_REPONAME}:$TAG"
          doctl auth init -t $DIGITALOCEAN_TOKEN
          doctl kubernetes cluster kubeconfig save $CLUSTER_NAME

          terraform -chdir=./terraform/do_k8s_deploy_app apply \
            -var do_token=$DIGITALOCEAN_TOKEN \
            -var cluster_name=$CLUSTER_NAME \
            -var docker_image=$DOCKER_IMAGE \
            -auto-approve

          # Save the Load Balancer Public IP Address
          export ENDPOINT="$(terraform -chdir=./terraform/do_k8s_deploy_app output lb_public_ip)"
          mkdir -p /tmp/do_k8s/
          echo 'export ENDPOINT='${ENDPOINT} > /tmp/do_k8s/dok8s-endpoint
    - persist_to_workspace:
        root: /tmp/do_k8s/
        paths:
          - '*'

```

- Add the new job to the workflow - add `requires` statements to only start deployment when cluster creation job has completed

```yaml
workflows:
  test_scan_deploy:
    jobs:
      ...
      - create_do_k8s_cluster:
          context:
            - cicd-workshop
          requires:
            - build
            - test
            - lint
            - build_docker_image
            - dependency_vulnerability_scan
      - deploy_to_k8s:
          requires:
            - create_do_k8s_cluster
          context:
            - cicd-workshop

```

- Now that our application has been deployed it should be running on our brand new Kubernetes cluster! Yay us, but it's not yet time to call it a day. We need to verify that the app is actually running, and for that we need to test in production. Let's introduce something called a Smoke test!


- Add a new job - `smoketest_k8s_deployment. This uses a bash script to make HTTP requests to the deployed app and verifies the responses are what we expect. We also use a CircleCI Workspace to pass the endpoint of the deployed application to our test.

```yaml
smoketest_k8s_deployment:
  docker:
    - image: cimg/base:stable
  steps:
    - checkout
    - attach_workspace:
        at: /tmp/do_k8s/
    - run:
        name: Smoke Test K8s App Deployment
        command: |
          source /tmp/do_k8s/dok8s-endpoint
          ./test/smoke_test $ENDPOINT

```

- Add the smoke test job to the workflow, so it's dependent on `deploy_to_k8s`:

```yaml
workflows:
  build_test_deploy:
    jobs:
      ...
      - create_do_k8s_cluster:
            context:
              - cicd-workshop
            requires:
              - build
              - test
              - lint
              - build_docker_image
              - dependency_vulnerability_scan
        - deploy_to_k8s:
            requires:
              - create_do_k8s_cluster
            context:
              - cicd-workshop
        - smoketest_k8s_deployment:
            requires:
              - deploy_to_k8s

```

### Tear down the infrastructure

The last step of this chapter is to tear down the infrastructure we provisioned, and "undeploy" the application. This will ensure you're not charged for keeping these resources up and running. We will combine it with an approval step that only triggers when we manually click approve (who said CI/CD was all about automation?)

- Create a new job - `destroy_k8s_cluster`:

```yaml
destroy_k8s_cluster:
  docker:
    - image: cimg/base:stable
  steps:
    - checkout
    - install_doctl:
        version: 1.78.0
    - run:
        name: Create .terraformrc file locally
        command: echo "credentials \"app.terraform.io\" {token = \"$TF_CLOUD_KEY\"}" > $HOME/.terraformrc && cat $HOME/.terraformrc
    - terraform/install:
        terraform_version: 1.0.6
        arch: amd64
        os: linux
    - terraform/init:
        path: ./terraform/do_k8s_deploy_app/
    - run:
        name: Destroy App Deployment
        command: |
          export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}
          export TAG=0.1.<< pipeline.number >>
          export DOCKER_IMAGE="${DOCKER_LOGIN}/${CIRCLE_PROJECT_REPONAME}:$TAG"
          doctl auth init -t $DIGITALOCEAN_TOKEN
          doctl kubernetes cluster kubeconfig save $CLUSTER_NAME

          terraform -chdir=./terraform/do_k8s_deploy_app/ apply -destroy \
            -var do_token=$DIGITALOCEAN_TOKEN \
            -var cluster_name=$CLUSTER_NAME \
            -var docker_image=$DOCKER_IMAGE \
            -auto-approve

    - terraform/init:
        path: ./terraform/do_create_k8s
    - run:
        name: Destroy K8s Cluster
        command: |
          export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}
          export DO_K8S_SLUG_VER="$(doctl kubernetes options versions \
            -o json -t $DIGITALOCEAN_TOKEN | jq -r '.[0] | .slug')"

          terraform -chdir=./terraform/do_create_k8s apply -destroy \
            -var do_token=$DIGITALOCEAN_TOKEN \
            -var cluster_name=$CLUSTER_NAME \
            -var do_k8s_slug_ver=$DO_K8S_SLUG_VER \
            -auto-approve
```

This runs two Terraform steps - with the, running `apply -destroy` which basically undoes them. First the deployment, and then the underlying infrastructure.

- Now add the destroy job to the workflow.


```yaml
workflows:
  build_test_deploy:
    jobs:
    ...
     - deploy_to_k8s:
            requires:
              - create_do_k8s_cluster
            context:
              - cicd-workshop
        - smoketest_k8s_deployment:
            requires:
              - deploy_to_k8s
        - destroy_k8s_cluster:
            requires:
              - smoketest_k8s_deployment
            context:
              - cicd-workshop
```

🎉 Congratulations! You have reached to the end of chapter 2 with a fully fledged Kubernetes provisioning and deployment in a CI/CD pipeline!


## Chapter 3 - Advanced deployments to multiple environments

In the final chapter we will introduce another environment - `prod`, and name our current environment `test`. It will let us test first, then only deploy to production when ready. We will also learn how to use parameters to re-use large parts of the config in our workflows.

To get to the starting point, run:

```bash
./scripts/chapter_3.sh
```

### Parameters in jobs

First, let's introduce the `env` parameter to specify environment name.

```yaml
  create_do_k8s_cluster:
    parameters:
      env:
        type: string
        default: test
    docker:
      - image: cimg/base:stable
    steps:
      - checkout
      - install_doctl:
          version: "1.78.0"
      - run:
          name: Create .terraformrc file locally
          command: echo "credentials \"app.terraform.io\" {token = \"$TF_CLOUD_KEY\"}" > $HOME/.terraformrc
      - terraform/install:
          terraform_version: "1.0.6"
          arch: "amd64"
          os: "linux"
      - terraform/init:
          path: ./terraform/do_create_k8s
      - run:
          name: Create K8s Cluster on DigitalOcean
          command: |
            export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}-<< parameters.env >>
            export DO_K8S_SLUG_VER="$(doctl kubernetes options versions \
              -o json -t $DIGITALOCEAN_TOKEN | jq -r '.[0] | .slug')"
            terraform -chdir=./terraform/do_create_k8s apply \
              -var do_token=$DIGITALOCEAN_TOKEN \
              -var cluster_name=$CLUSTER_NAME \
              -var do_k8s_slug_ver=$DO_K8S_SLUG_VER \
              -auto-approve
```

We can use this parameter in the steps by referring to it as `<< parameters.env >>`.

Do the same for deployment and destroy jobs.

Deployment:

```yaml
  deploy_to_k8s:
    parameters:
      env:
        type: string
        default: test
    docker:
      - image: cimg/base:stable
    steps:
      - checkout
      - install_doctl:
          version: "1.78.0"
      - run:
          name: Create .terraformrc file locally
          command: echo "credentials \"app.terraform.io\" {token = \"$TF_CLOUD_KEY\"}" > $HOME/.terraformrc
      - terraform/install:
          terraform_version: "1.0.6"
          arch: "amd64"
          os: "linux"
      - terraform/init:
          path: ./terraform/do_k8s_deploy_app
      - run:
          name: Deploy Application to K8s on DigitalOcean
          command: |
            export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}-<< parameters.env >>
            export TAG=0.1.<< pipeline.number >>
            export DOCKER_IMAGE="${DOCKER_LOGIN}/${CIRCLE_PROJECT_REPONAME}:$TAG"
            doctl auth init -t $DIGITALOCEAN_TOKEN
            doctl kubernetes cluster kubeconfig save $CLUSTER_NAME
            terraform -chdir=./terraform/do_k8s_deploy_app apply \
              -var do_token=$DIGITALOCEAN_TOKEN \
              -var cluster_name=$CLUSTER_NAME \
              -var docker_image=$DOCKER_IMAGE \
              -auto-approve
            # Save the Load Balancer Public IP Address
            export ENDPOINT="$(terraform -chdir=./terraform/do_k8s_deploy_app output lb_public_ip)"
            mkdir -p /tmp/do_k8s/
            echo 'export ENDPOINT='${ENDPOINT} > /tmp/do_k8s/dok8s-endpoint
      - persist_to_workspace:
          root: /tmp/do_k8s/
          paths:
            - "*"
```

Destruction job:

```yaml
 destroy_k8s_cluster:
    parameters:
      env:
        type: string
        default: test
    docker:
      - image: cimg/base:stable
    steps:
      - checkout
      - install_doctl:
          version: "1.78.0"
      - run:
          name: Create .terraformrc file locally
          command: echo "credentials \"app.terraform.io\" {token = \"$TF_CLOUD_KEY\"}" > $HOME/.terraformrc && cat $HOME/.terraformrc
      - terraform/install:
          terraform_version: "1.0.6"
          arch: "amd64"
          os: "linux"
      - terraform/init:
          path: ./terraform/do_k8s_deploy_app/
      - run:
          name: Destroy App Deployment
          command: |
            export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}-<< parameters.env >>
            export TAG=0.1.<< pipeline.number >>
            export DOCKER_IMAGE="${DOCKER_LOGIN}/${CIRCLE_PROJECT_REPONAME}:$TAG"
            doctl auth init -t $DIGITALOCEAN_TOKEN
            doctl kubernetes cluster kubeconfig save $CLUSTER_NAME
            terraform -chdir=./terraform/do_k8s_deploy_app/ apply -destroy \
              -var do_token=$DIGITALOCEAN_TOKEN \
              -var cluster_name=$CLUSTER_NAME \
              -var docker_image=$DOCKER_IMAGE \
              -auto-approve
      - terraform/init:
          path: ./terraform/do_create_k8s
      - run:
          name: Destroy K8s Cluster
          command: |
            export CLUSTER_NAME=${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}-<< parameters.env >>
            export DO_K8S_SLUG_VER="$(doctl kubernetes options versions \
              -o json -t $DIGITALOCEAN_TOKEN | jq -r '.[0] | .slug')"
            terraform -chdir=./terraform/do_create_k8s apply -destroy \
              -var do_token=$DIGITALOCEAN_TOKEN \
              -var cluster_name=$CLUSTER_NAME \
              -var do_k8s_slug_ver=$DO_K8S_SLUG_VER \
              -auto-approve

```

Now our jobs take parameters we need to also pass them. We do that in the workflows. We will also specify a unique name for these jobs inside a workflow, so we can refer to them later.

```yaml
workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
        - build_docker_image:
            context:
              - cicd-workshop
        - dependency_vulnerability_scan:
            context:
              - cicd-workshop
        - create_do_k8s_cluster:
            name: create_test_cluster
            env: test
            context:
              - cicd-workshop
            requires:
              - build
              - test
              - lint
              - build_docker_image
              - dependency_vulnerability_scan
        - deploy_to_k8s:
            name: deploy_test
            env: test
            requires:
              - create_test_cluster
            context:
              - cicd-workshop
        - smoketest_k8s_deployment:
            requires:
              - deploy_test
        - destroy_k8s_cluster:
            name: destroy_test_cluster
            env: test
            requires:
              - smoketest_k8s_deployment
            context:
              - cicd-workshop
```

Now we have a clearly labeled test environment, so we can move on to production. Before we do that we want to make sure someone manually approves it though. We will introduce a special approval job for that:

```yaml

workflows:
  build_test_deploy:
      jobs:
        ...
        - destroy_k8s_cluster:
            name: destroy_test_cluster
            env: test
            requires:
              - smoketest_k8s_deployment
            context:
              - cicd-workshop
        - approve_prod_deploy:
            type: approval
            requires:
              - destroy_test_cluster
```

After approval we can move on to production deployment. Because of parameters there is much less code to write, just add the `prod` references in the `env` params. We will also add a prod destroy approval for good measure.

```yaml
workflows:
  build_test_deploy:
      jobs:
        - build
        - test
        - lint
        - build_docker_image:
            context:
              - cicd-workshop
        - dependency_vulnerability_scan:
            context:
              - cicd-workshop
        - create_do_k8s_cluster:
            name: create_test_cluster
            env: test
            context:
              - cicd-workshop
            requires:
              - build
              - test
              - lint
              - build_docker_image
              - dependency_vulnerability_scan
        - deploy_to_k8s:
            name: deploy_test
            env: test
            requires:
              - create_test_cluster
            context:
              - cicd-workshop
        - smoketest_k8s_deployment:
            requires:
              - deploy_test
        - destroy_k8s_cluster:
            name: destroy_test_cluster
            env: test
            requires:
              - smoketest_k8s_deployment
            context:
              - cicd-workshop
        - approve_prod_deploy:
            type: approval
            requires:
              - destroy_test_cluster
        - create_do_k8s_cluster:
            name: create_prod_cluster
            env: prod
            requires:
              - approve_prod_deploy
            context:
              - cicd-workshop
        - deploy_to_k8s:
            name: deploy_prod
            env: prod
            context:
              - cicd-workshop
            requires:
              - create_prod_cluster
        - approve_prod_destroy:
            type: approval
            requires:
              - deploy_prod
        - destroy_k8s_cluster:
            name: destroy_prod_cluster
            env: prod
            context:
              - cicd-workshop
            requires:
              - approve_prod_destroy
```

Now you have implemented deployments to two different environments. Let's make sure production only happens when pushing to the main branch.

Change the `approve_prod_deploy` job in the workflow to add a filter to it:

```yaml
- approve_prod_deploy:
    type: approval
    requires:
      - destroy_test_cluster
    filters:
      branches:
        only:
          - main

```

 Congratulations, you have completed the CircleCI part of the workshop! Now let's learn about Cypress!

 You can jump to this latest stage by running `./scripts/chapter_3.sh`
