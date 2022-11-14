# CircleCI and Cypress Workshop

## Prerequisites

Knowledge of Git version control system
GitHub account - where the code is hosted
A code editor - Visual Studio Code is preferred but you can use anything


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

#### DigitalOcean

- Create an account with DigitalOcean - https://cloud.digitalocean.com/ We will use DigitalOcean to deploy our application to. 
- Go to API (left)
- Generate New Token with read and write access
- copy the token string to `credentials.toml` - `digitalocean_token`
- The workshop host will provide a coupon code for you to use.
 
#### Terraform Cloud

- Create an account with Hashicorp Terraform - https://app.terraform.io/ We will use Terraform to provision our infrastructure on Digital Ocean.
- Got to your user settings (top right), and select Tokens
- Create an API token 
- Copy the token string to `credentials.toml` - `tf_cloud_key`

#### Docker Hub

- Create an account with Docker Hub - https://hub.docker.com/ We will use Docker Hub as a repository for our app images.
- Go to your user settings (top right), and select Security
- Create New Access Token
- copy your username to `credentials.toml` - `docker_username`
- copy your token string to `credentials.toml` - `docker_token`

#### Snyk

- Create an account with Snyk - https://app.snyk.io/ - We will use Snyk to run an automated security scan of our application an its dependencies. 
- Go to your Account settings (top right)
- Click to show Auth Token 
- Copy your token string to `credentials.toml` - `snyk_token`

### How this workshop works

We will go from a chapter to chapter - depending on people's background we might skip a chapter (Chapter 1 is for complete beginners to CI/CD and subsequent chapters build on top of that, for example).

To jump between chapters we have prepared a set of handy scripts you can run in your terminal, which will set up your environment so you can follow along.

The scripts to run are:

`./scripts/do_1_start.sh` - Beginning of first stage
`./scripts/do_2.sh` - End of first stage/Start of second stage
`./scripts/do_3.sh` - End of second stage/Start of third stage
`./scripts/do_4.sh` - Final state

The chapters will copy and overwrite certain files in your workspace, so after running each script, commit the changes and push it, which will run it on CircleCI.

### Overview of the project

The project is a simple web application based on the Vitesse project, that is packaged in a Docker container, and deployed on Kubernetes - hosted on DigitalOcean infrastructure. 
We also have some tests, a security scan, building the image, provisioning the infrastructure and deploying the application.

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
This workshop is written in chapters, so you can jump between them by running scripts in `srcipts/` dir, if you get lost and want to catch up with something.
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
            npm run test
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
            npm run test
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
            npm run test

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
            key: v1-deps-{{ checksum "package-lock.json" }}
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
            npm run test

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

- Report test results to CircleCI. Change `test-ci` job in `package.json` to export test results in JUnit format.

```json
{
  ...
  "scripts":
  {
    ...
    "test-ci": "vitest run --reporter=junit --outputFile output/results.xml",
    ...
  } 
  ...
}
```

- Add the following run commands to `build_and_test` job:

```yaml
jobs:
  build_and_test:
    ...
      - run:
          name: Run tests
          command: npm run test-ci
      - run:
          name: Copy tests results for storing
          command: |
            cp test-results.xml test-results/
          when: always
      - store_test_results:
          path: test-results
      - store_artifacts:
          path: test-results
```

- Utilise cache for dependencies to avoid installing each time:

```yaml
jobs:
    build_and_test:
    ...
    steps:
        - checkout
        - restore_cache:
            key: v1-deps-{{ checksum "package-lock.json" }}
        - run:
            name: Install deps
            command: npm install
        - save_cache:
            key: v1-deps-{{ checksum "package-lock.json" }}
            paths: 
                - node_modules   
        - run:
            name: Run tests
            command: npm run test-ci

```

### Using the orb instead of installing and caching dependencies manually

Now let's replace our existing process for dependency installation and running tests by using an orb - this saves you a lot of configuration and manages caching for you. Introduce the orb: 

```yaml
version: 2.1

orbs:
  node: circleci/node@5.0.2
```

- Replace the job caching and dependency installation code with the call to the `node/install_packages` in the Node orb:

```yaml
jobs:
  build_and_test:
    ...
    steps:
        - checkout
        - node/install-packages
        - run:
            name: Run tests
            command: npm run test-ci
```

### Secrets and Contexts

CircleCI lets you store secrets safely on the platform where they will be encrypted and only made available to the executors as environment variables. The first secrets you will need are credentials for Docker Hub which you'll use to deploy your image to Docker Hub.

We have prepared a script for you to create a context and set it up with all the secrets you will need in CircleCI. This will use the CircleCI API.

You should have all the required accounts for third party services already, and are just missing the CircleCI API token and the organization ID:

- In app.circleci.com click on your user image (bottom left)
- Go to Personal API Tokens 
- Generate new API token and insert it `credentials.toml`
- In app.circleci.com click on the Organization settings. 
- Copy the Organization ID value and insert it in `credentials.toml`

Make sure that you have all the required service variables set in `credentials.toml`, and then run the script:

```bash
python scripts/prepare_contexts.py
```

Most of the things you do in CircleCI web interface can also be done with the API. You can inspect the newly created context and secrets by going to your organization settings. Now we can create a new job to build and deploy a Docker image.

### Building and deploying a Docker image

- First introduce the Docker orb:

```yaml
orbs:
  node: circleci/node@5.0.2
  docker: circleci/docker@2.1.1
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

In the workflow, add the deployment job:

```yaml
workflows:
  test_scan_deploy:
    jobs:
      - build_and_test
      - build_docker_image

```

This doesn't run unfortunately - our `build_docker_image` doesn't have the required credentials. 
Add the context we created earlier:

```yaml
workflows:
  test_scan_deploy:
    jobs:
      - build_and_test
      - build_docker_image:
          context:
            - cicd-workshop
```

This runs both jobs in parallel. We might want to run them sequentially instead, so Docker deployment only happens when the tests have passed. Do this by adding a `requires` stanza to the `build_docker_image` job:

```yaml
workflows:
  test_scan_deploy:
    jobs:
      - build_and_test
      - build_docker_image:
          context:
            - cicd-workshop
          requires:
            - build_and_test
```

🎉 Congratulations, you've completed the first part of the exercise!

## Chapter 2 - A realistic CI/CD pipeline

In this section you will learn about cloud native paradigms, shift left security scanning, infrastructure provisioning, and deployment of infrastructure!

If you got lost in the previous chapter, the initial state of the configuration is in `scripts/do/configs/config_2.yml`. You can restore it by running `./scripts/do_2.sh`.

### Integrate automated dependency vulnerability scan

- First let's integrate a security scanning tool in our process. We will use Snyk, for which you should already have the account created and environment variable set.

- Add Snyk orb: 

```yaml
orbs:
  node: circleci/node@5.0.2
  docker: circleci/docker@2.1.1
  snyk: snyk/snyk@1.2.3
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
  test_scan_deploy:
    jobs:
      - build_and_test
      - dependency_vulnerability_scan:
          context:
            - cicd-workshop
      - build_docker_image:
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

### Cloud Native deployments

We often use CI/CD pipelines to create our infrastructure, not just run our applications. In the following steps we will be doing just that.

First make sure you have all the credentials created and set in your `cicd-workshop` context:
- DIGITALOCEAN_TOKEN
- TF_CLOUD_KEY

This tells a cloud provider - in our case Digitalocean - what to create for us, so we can deploy our application. We will use a tool called Terraform for it.

- Add the orb for Terraform

```yaml
orbs:
  node: circleci/node@5.0.2
  docker: circleci/docker@2.1.1
  snyk: snyk/snyk@1.2.3
  terraform: circleci/terraform@3.0.0
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
          export CLUSTER_NAME=${CIRCLE_PROJECT_REPONAME}
          export DO_K8S_SLUG_VER="$(doctl kubernetes options versions \
            -o json -t $DIGITAL_OCEAN_TOKEN | jq -r '.[0] | .slug')"

          terraform -chdir=./terraform/do_create_k8s apply \
            -var do_token=$DIGITAL_OCEAN_TOKEN \
            -var cluster_name=$CLUSTER_NAME \
            -var do_k8s_slug_ver=$DO_K8S_SLUG_VER \
            -auto-approve

```

Add the new job to the workflow. Add `requires` statements to only start deployment when all prior steps have completed

```yaml
workflows:
  test_scan_deploy:
    jobs:
      - build_and_test
      - dependency_vulnerability_scan:
          context:
            - cicd-workshop
      - build_docker_image:
          context:
            - cicd-workshop
      - create_do_k8s_cluster:
          requires:
            - dependency_vulnerability_scan
            - build_docker_image
            - build_and_test
          context:
            - cicd-workshop

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
          export CLUSTER_NAME=${CIRCLE_PROJECT_REPONAME}
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
  test_scan_deploy:
    jobs:
      - build_and_test
      - dependency_vulnerability_scan:
          context:
            - cicd-workshop
      - build_docker_image:
          context:
            - cicd-workshop
      - create_do_k8s_cluster:
          context:
            - cicd-workshop
      - deploy_to_k8s:
          requires:
            - dependency_vulnerability_scan
            - build_docker_image
            - build_and_test
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
          export CLUSTER_NAME=${CIRCLE_PROJECT_REPONAME}
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
          export CLUSTER_NAME=${CIRCLE_PROJECT_REPONAME}
          export DO_K8S_SLUG_VER="$(doctl kubernetes options versions \
            -o json -t $DIGITALOCEAN_TOKEN | jq -r '.[0] | .slug')"

          terraform -chdir=./terraform/do_create_k8s apply -destroy \
            -var do_token=$DIGITALOCEAN_TOKEN \
            -var cluster_name=$CLUSTER_NAME \
            -var do_k8s_slug_ver=$DO_K8S_SLUG_VER \
            -auto-approve
```

This runs two Terraform steps - with the, running `apply -destroy` which basically undoes them. First the deployment, and then the underlying infrastructure.

- Now add the destroy job to the workflow, alongside a new `approve_destroy` job:

```yaml
workflows:
  test_scan_deploy:
    jobs:
      - build_and_test
      - dependency_vulnerability_scan:
          context:
            - cicd-workshop
      - build_docker_image:
          context:
            - cicd-workshop
      - create_do_k8s_cluster:
          context:
            - cicd-workshop
      - deploy_to_k8s:
          requires:
            - dependency_vulnerability_scan
            - build_docker_image
            - build_and_test
            - create_do_k8s_cluster
          context:
            - cicd-workshop
      - smoketest_k8s_deployment:
          requires:
            - deploy_to_k8s
      - approve_destroy:
          type: approval
          requires:
            - smoketest_k8s_deployment
      - destroy_k8s_cluster:
          requires:
            - approve_destroy
          context:
            - cicd-workshop
```

The `approve_destroy` had a special type set - `approval` which means we don't have to define it and it will give us the option to manually confirm we want to continue executing the workflow.

🎉 Congratulations! You have reached to the end of chapter 2 with a fully fledged Kubernetes provisioning and deployment in a CI/CD pipeline!


## Chapter 3 - Advanced CI/CD 

Let's pretend a few months have passed, you have been working on your application for a while and noticed the tests now run a lot longer than they used to! In this chapter we will be focusing on improving the pipeline itself.

To get to the starting point, run:

```bash
./scripts/do_3.sh 
```

This will copy over a bunch of long running tests to simulate your application growing. Commit and see that tests now run for around 5 minutes, much longer than before.

### Choosing what gets run by filtering branches

We sometimes don't want to run the entire pipeline on every commit - maybe we only want to conduct the deployment when merging into the `main` branch, but not on feature branches. Let's do that now.

Add a `filters` section to your cluster creation step:

```yaml
workflows:
  run-tests:
    jobs:
      ...
      - create_do_k8s_cluster:
          requires:
            - dependency_vulnerability_scan
            - build_docker_image
            - build_and_test
          context:
            - cicd-workshop
          filters:
            branches:
              only: main
      ...
```

While you are on a non `main` branch, you will always skip the infrastructure provisioning and deployment jobs. This will have the extra benefit of making your build times much shorter during this workshop :) 

### Employing parallelism - splitting long running tests

- To make our tests run faster we can try several things. My favourite is employing parallelism and run them across multiple parallel jobs. First introduce the parallelism value in `build_and_test` job:

```yaml
jobs:
  build_and_test:
    docker:
      - image: cimg/node:16.16.0
    parallelism: 4
    steps:
      ...

```

This tells CircleCI to spin up 4 parallel jobs. Now we need to change the run script to only run a subset of all the tests in each job, and then collate the results:

```yaml
jobs:
  build_and_test:
    docker:
      - image: cimg/node:16.16.0
    parallelism: 4
    steps:
      - checkout
      - node/install-packages
      - run:
          name: Run tests
          command: |
            echo $(circleci tests glob "test/**/*.test.js")
            circleci tests glob "test/**/*.test.js" | circleci tests split |
            xargs npm run test-ci
      - run:
          name: Copy tests results for storing
          command: |
            mkdir test-results
            cp test-results.xml test-results/
          when: always
      - run:
          name: Process test report
          command: |
            # Convert absolute paths to relative to support splitting tests by timing
            if [ -e test-results.xml ]; then
              sed -i "s|`pwd`/||g" test-results.xml
            fi
      - store_test_results:
          path: test-results
      - store_artifacts:
          path: test-results

```

Commit and run the tests again and you will see them run in much less time!

### Employing parallelism - running tests in a matrix

We often want to test the same code across different variants of the application. We can employ matrix with CircleCI for that.

- Create a new job parameter for `build_and_test` job, and use its value in the selected image:

```yaml
jobs:
  build_and_test:
    parameters:
      node_version:
        type: string
        default: 16.16.0
    docker:
      - image: cimg/node:<< parameters.node_version >>
    steps:
      - checkout
```

- Pass matrix of versions as parameters for the job in the workflow definition:

```yaml
workflows:
  run-tests:
    jobs:
      - build_and_test:
          matrix:
            parameters:
              node_version: ["16.16.0", "14.19.0", "17.6.0" ]
      - dependency_vulnerability_scan
      ...
```

### Run a nightly scheduled pipeline


- In `Project Settings` choose the `Triggers` tab and add a new trigger. Set it to run each day at 0:00 UTC, 1 per hour, off `main` branch. Add pipeline parameter `scheduled` set to `true`.

- Create a new boolean pipeline parameter in the config - `scheduled` which defaults to false:

```yaml
parameters:
  scheduled:
    type: boolean
    default: false
```

- Create a new workflow called `nightly_build` that only runs when `scheduled` is true:

```yaml
workflows:
  ...
  nightly-build:
    when: << pipeline.parameters.scheduled >>
    jobs:
      - build_and_test:
          matrix:
            parameters:
              node_version: ["16.16.0", "14.19.0", "17.6.0" ]
      - dependency_vulnerability_scan
      - build_docker_image:
            context:
              - cicd-workshop
```

- Add the `when/not` rule to the `run-tests` workflow:

```yaml
workflows:
  test_scan_deploy:
    when:
      not: << pipeline.parameters.scheduled >>
    jobs:
      - build_and_test:
      ...
```

This effectively lets us to route the workflow execution based on the pipeline parameter which is set.

🎉 Contratulations, you have completed the chapter, and optimised your CI/CD pipeline further!

## Chapter 4 - Dynamic Config

You can reset the state for this by running `.scripts/do_4.sh`

So far our config has been pretty straightforward. Trigger on commit or schedule would run our pipeline. But sometimes we want more flexibility, based on some external factors.

Dynamic config lets you change what your pipeline does while it's already running, based on git history, changes, or external factors.

- Toggle dynamic config in project settings - Advanced
- Copy your existing `config.yml` to `.circleci/continue-config.yml`:

```bash
cp .circleci/config.yml .circleci/continue-config.yml
```

- Add `setup: true` stanza to your `config.yml`: 

```yaml
version: 2.1

setup: true
...
```

- Add the `path-filtering` orb (and remove others) in `config.yml`

```yaml
orbs:
  path-filtering: circleci/path-filtering@0.1.1
  continuation: circleci/continuation@0.2.0
```

- Remove all jobs and workflows in `config.yml` and replace with the following:

```yaml
jobs:
  filter-paths:
    docker:
      - image: cimg/base:stable
    steps:
      - checkout
      - path-filtering/set-parameters:
          base-revision: main
          mapping: |
            scripts/.*     skip-run  true
          output-path: /tmp/pipeline-parameters.json
      - continuation/continue:
          configuration_path: .circleci/continue-config.yml
          parameters: /tmp/pipeline-parameters.json
workflows:
  choose-config:
    jobs:
      - filter-paths
```

Add the pipeline parameter for our scheduled pipeline

```yaml
parameters:
  scheduled:
    type: boolean
    default: false
```

- In `continue-config.yml` add the the `skip-run` pipeline parameter:

```yaml
parameters:
  skip-run:
    type: boolean
    default: false
  scheduled:
    type: boolean
    default: false
```

- Add the `skip-run` parameters to `when not` condition in the `test_scan_deploy` workflow:

```yaml
workflows:
  run-tests:
    when:
      and: 
        - not: << pipeline.parameters.scheduled >>
        - not: << pipeline.parameters.skip-run >>
    jobs:
      - build_and_test:
      ...
```

That's it - you have completed our workshop!


# Vitesse project README ⬇️

<p align='center'>
  <img src='https://user-images.githubusercontent.com/11247099/154486817-f86b8f20-5463-4122-b6e9-930622e757f2.png' alt='Vitesse - Opinionated Vite Starter Template' width='600'/>
</p>

<p align='center'>
Mocking up web app with <b>Vitesse</b><sup><em>(speed)</em></sup><br>
</p>

<br>

<p align='center'>
<a href="https://vitesse.netlify.app/">Live Demo</a>
</p>

<br>

<p align='center'>
<b>English</b> | <a href="https://github.com/antfu/vitesse/blob/main/README.zh-CN.md">简体中文</a>
<!-- Contributors: Thanks for getting interested, however we DON'T accept new transitions to the README, thanks. -->
</p>

<br>


## Features

- ⚡️ [Vue 3](https://github.com/vuejs/core), [Vite 3](https://github.com/vitejs/vite), [pnpm](https://pnpm.io/), [ESBuild](https://github.com/evanw/esbuild) - born with fastness

- 🗂 [File based routing](./src/pages)

- 📦 [Components auto importing](./src/components)

- 🍍 [State Management via Pinia](https://pinia.vuejs.org/)

- 📑 [Layout system](./src/layouts)

- 📲 [PWA](https://github.com/antfu/vite-plugin-pwa)

- 🎨 [UnoCSS](https://github.com/antfu/unocss) - the instant on-demand atomic CSS engine

- 😃 [Use icons from any icon sets with classes](https://github.com/antfu/unocss/tree/main/packages/preset-icons)

- 🌍 [I18n ready](./locales)

- 🔎 [Component Preview](https://github.com/johnsoncodehk/vite-plugin-vue-component-preview)

- 🗒 [Markdown Support](https://github.com/antfu/vite-plugin-vue-markdown)

- 🔥 Use the [new `<script setup>` syntax](https://github.com/vuejs/rfcs/pull/227)

- 🤙🏻 [Reactivity Transform](https://vuejs.org/guide/extras/reactivity-transform.html) enabled

- 📥 [APIs auto importing](https://github.com/antfu/unplugin-auto-import) - use Composition API and others directly

- 🖨 Static-site generation (SSG) via [vite-ssg](https://github.com/antfu/vite-ssg)

- 🦔 Critical CSS via [critters](https://github.com/GoogleChromeLabs/critters)

- 🦾 TypeScript, of course

- ⚙️ Unit Testing with [Vitest](https://github.com/vitest-dev/vitest), E2E Testing with [Cypress](https://cypress.io/) on [GitHub Actions](https://github.com/features/actions)

- ☁️ Deploy on Netlify, zero-config

<br>


## Pre-packed

### UI Frameworks

- [UnoCSS](https://github.com/antfu/unocss) - The instant on-demand atomic CSS engine.

### Icons

- [Iconify](https://iconify.design) - use icons from any icon sets [🔍Icônes](https://icones.netlify.app/)
- [Pure CSS Icons via UnoCSS](https://github.com/antfu/unocss/tree/main/packages/preset-icons)

### Plugins

- [Vue Router](https://github.com/vuejs/router)
  - [`vite-plugin-pages`](https://github.com/hannoeru/vite-plugin-pages) - file system based routing
  - [`vite-plugin-vue-layouts`](https://github.com/JohnCampionJr/vite-plugin-vue-layouts) - layouts for pages
- [Pinia](https://pinia.vuejs.org) - Intuitive, type safe, light and flexible Store for Vue using the composition api
- [`unplugin-vue-components`](https://github.com/antfu/unplugin-vue-components) - components auto import
- [`unplugin-auto-import`](https://github.com/antfu/unplugin-auto-import) - Directly use Vue Composition API and others without importing
- [`vite-plugin-pwa`](https://github.com/antfu/vite-plugin-pwa) - PWA
- [`vite-plugin-vue-component-preview`](https://github.com/johnsoncodehk/vite-plugin-vue-component-preview) - Preview single component in VSCode
- [`vite-plugin-vue-markdown`](https://github.com/antfu/vite-plugin-vue-markdown) - Markdown as components / components in Markdown
  - [`markdown-it-shiki`](https://github.com/antfu/markdown-it-shiki) - [Shiki](https://github.com/shikijs/shiki) for syntax highlighting
- [Vue I18n](https://github.com/intlify/vue-i18n-next) - Internationalization
  - [`vite-plugin-vue-i18n`](https://github.com/intlify/bundle-tools/tree/main/packages/vite-plugin-vue-i18n) - Vite plugin for Vue I18n
- [VueUse](https://github.com/antfu/vueuse) - collection of useful composition APIs
- [`vite-ssg-sitemap`](https://github.com/jbaubree/vite-ssg-sitemap) - Sitemap generator
- [`@vueuse/head`](https://github.com/vueuse/head) - manipulate document head reactively

### Coding Style

- Use Composition API with [`<script setup>` SFC syntax](https://github.com/vuejs/rfcs/pull/227)
- [ESLint](https://eslint.org/) with [@antfu/eslint-config](https://github.com/antfu/eslint-config), single quotes, no semi.

### Dev tools

- [TypeScript](https://www.typescriptlang.org/)
- [Vitest](https://github.com/vitest-dev/vitest) - Unit testing powered by Vite
- [Cypress](https://cypress.io/) - E2E testing
- [pnpm](https://pnpm.js.org/) - fast, disk space efficient package manager
- [`vite-ssg`](https://github.com/antfu/vite-ssg) - Static-site generation
  - [critters](https://github.com/GoogleChromeLabs/critters) - Critical CSS
- [Netlify](https://www.netlify.com/) - zero-config deployment
- [VS Code Extensions](./.vscode/extensions.json)
  - [Vite](https://marketplace.visualstudio.com/items?itemName=antfu.vite) - Fire up Vite server automatically
  - [Volar](https://marketplace.visualstudio.com/items?itemName=Vue.volar) - Vue 3 `<script setup>` IDE support
  - [Iconify IntelliSense](https://marketplace.visualstudio.com/items?itemName=antfu.iconify) - Icon inline display and autocomplete
  - [i18n Ally](https://marketplace.visualstudio.com/items?itemName=lokalise.i18n-ally) - All in one i18n support
  - [ESLint](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint)

## Variations

As this template is strongly opinionated, the following provides a curated list for community-maintained variations with different preferences and feature sets. Check them out as well. PR to add yours is also welcome!

###### Official

- [vitesse-lite](https://github.com/antfu/vitesse-lite) - Lightweight version of Vitesse
- [vitesse-nuxt3](https://github.com/antfu/vitesse-nuxt3) - Vitesse for Nuxt 3
- [vitesse-nuxt-bridge](https://github.com/antfu/vitesse-nuxt-bridge) - Vitesse for Nuxt 2 with Bridge
- [vitesse-webext](https://github.com/antfu/vitesse-webext) - WebExtension Vite starter template

###### Community

- [vitesse-ssr-template](https://github.com/frandiox/vitesse-ssr-template) by [@frandiox](https://github.com/frandiox) - Vitesse with SSR
- [vitespa](https://github.com/ctholho/vitespa) by [@ctholho](https://github.com/ctholho) - Like Vitesse but without SSG/SSR
- [vitailse](https://github.com/zynth17/vitailse) by [@zynth17](https://github.com/zynth17) - Like Vitesse but with TailwindCSS
- [vitesse-modernized-chrome-ext](https://github.com/xiaoluoboding/vitesse-modernized-chrome-ext) by [@xiaoluoboding](https://github.com/xiaoluoboding) - ⚡️ Modernized Chrome Extension Manifest V3 Vite Starter Template
- [vitesse-stackter-clean-architect](https://github.com/shamscorner/vitesse-stackter-clean-architect) by [@shamscorner](https://github.com/shamscorner) - A modular clean architecture pattern in vitesse template
- [vitesse-enterprise](https://github.com/FranciscoKloganB/vitesse-enterprise) by [@FranciscoKloganB](https://github.com/FranciscoKloganB) - Consistent coding styles regardless of team-size.
- [vitecamp](https://github.com/nekobc1998923/vitecamp) by [@nekobc1998923](https://github.com/nekobc1998923) - Like Vitesse but without SSG/SSR/File based routing, includes Element Plus
- [vitesse-lite-react](https://github.com/lxy-yz/vitesse-lite-react) by [@lxy-yz](https://github.com/lxy-yz) - vitesse-lite React fork
- [vide](https://github.com/Nico-Mayer/vide) by [@nico-mayer](https://github.com/Nico-Mayer) - Vite superlight Beginner Starter Template
- [vitesse-h5](https://github.com/YunYouJun/vitesse-h5) by [@YunYouJun](https://github.com/YunYouJun) - Vitesse for Mobile
- [bat](https://github.com/olgam4/bat) by [@olgam4](https://github.com/olgam4) - Vitesse for SolidJS

## Try it now!

> Vitesse requires Node >=14.18

### GitHub Template

[Create a repo from this template on GitHub](https://github.com/antfu/vitesse/generate).

### Clone to local

If you prefer to do it manually with the cleaner git history

```bash
npx degit antfu/vitesse my-vitesse-app
cd my-vitesse-app
pnpm i # If you don't have pnpm installed, run: npm install -g pnpm
```

## Checklist

When you use this template, try follow the checklist to update your info properly

- [ ] Change the author name in `LICENSE`
- [ ] Change the title in `App.vue`
- [ ] Change the hostname in `vite.config.ts`
- [ ] Change the favicon in `public`
- [ ] Remove the `.github` folder which contains the funding info
- [ ] Clean up the READMEs and remove routes

And, enjoy :)

## Usage

### Development

Just run and visit http://localhost:3333

```bash
pnpm dev
```

### Build

To build the App, run

```bash
pnpm build
```

And you will see the generated file in `dist` that ready to be served.

### Deploy on Netlify

Go to [Netlify](https://app.netlify.com/start) and select your clone, `OK` along the way, and your App will be live in a minute.

### Docker Production Build

First, build the vitesse image by opening the terminal in the project's root directory.

```bash
docker buildx build . -t vitesse:latest
```

Run the image and specify port mapping with the `-p` flag.

```bash
docker run --rm -it -p 8080:80 vitesse:latest
```

## Why

I have created several Vite apps recently. Setting the configs up is kinda the bottleneck for me to make the ideas simply come true within a very short time.

So I made this starter template for myself to create apps more easily, along with some good practices that I have learned from making those apps. It's strongly opinionated, but feel free to tweak it or even maintain your own forks. [(see community maintained variation forks)](#variations)
