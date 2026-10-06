# shell-roboshop-new

Shell scripts to set up RoboShop on AWS. It follows the same steps as [roboshop-documentation](https://github.com/daws-92s/roboshop-documentation), only automated.

There are two kinds of scripts:

| Script | Where to run | What it does |
|--------|--------------|--------------|
| `roboshop.sh` | Your laptop or workstation, where the AWS CLI is configured | Creates security groups, rules, instances and Route53 records |
| `01-mongodb.sh` ... `11-frontend.sh` | On each server, as root | Installs and configures that component, then checks it is working |

---

## Before You Start

1. The AWS CLI is installed and configured (`aws configure`).
2. A Route53 hosted zone exists for your domain.
3. Replace `daws92s.store` with your domain in all files:

```shell
grep -rl daws92s.store . | xargs sed -i 's/daws92s.store/<your-domain>/g'
```

---

## Step 1: Create the Servers

```shell
./roboshop.sh create all
```

Or only some of them:

```shell
./roboshop.sh create mongodb catalogue
```

For every component the script makes sure that:

| Resource | Name | If it already exists |
|----------|------|----------------------|
| Security group | `roboshop-<component>` | Left as it is |
| Inbound rules | see the table below | Missing rules are added, existing ones are left |
| Instance | `roboshop-<component>` | Left as it is. A stopped instance is started |
| Route53 record | `<component>.<domain>` → private IP<br>`<domain>` → frontend public IP | Updated to the current IP |

So the script is safe to run again and again. Run it after you stop and start the instances: the public IP of the frontend changes, and the script updates the record.

At the end it prints all RoboShop instances with their IPs.

Security group rules (databases first, then backend, then frontend):

| Security group | Port | From |
|----------------|------|------|
| roboshop-mongodb | 27017 | roboshop-catalogue, roboshop-user |
| roboshop-redis | 6379 | roboshop-user, roboshop-cart |
| roboshop-mysql | 3306 | roboshop-shipping |
| roboshop-rabbitmq | 5672 | roboshop-payment, roboshop-dispatch |
| roboshop-catalogue | 8080 | roboshop-frontend, roboshop-cart |
| roboshop-user | 8080 | roboshop-frontend, roboshop-payment |
| roboshop-cart | 8080 | roboshop-frontend, roboshop-shipping, roboshop-payment |
| roboshop-shipping | 8080 | roboshop-frontend |
| roboshop-payment | 8080 | roboshop-frontend |
| roboshop-dispatch | - | no inbound port, it only connects out to RabbitMQ |
| roboshop-frontend | 80 | 0.0.0.0/0 |

Every security group also allows port 22 (SSH) from `SSH_CIDR`. It is `0.0.0.0/0` by default. Set it to `<your-ip>/32` at the top of `roboshop.sh` to allow SSH only from your laptop.

All security groups are created first, even when you create only one instance, because the rules point to each other.

To delete the instances:

```shell
./roboshop.sh delete all
```

Security groups and Route53 records are kept, they cost nothing and are reused next time.

---

## Step 2: Set Up Each Server

Log in to the server, then:

```shell
sudo su -
git clone https://github.com/daws-92s/shell-roboshop-new.git
cd shell-roboshop-new
bash 01-mongodb.sh
```

Run the scripts in this order, because each one needs the ones before it:

| Order | Server | Script | Needs |
|-------|--------|--------|-------|
| 1 | roboshop-mongodb | `01-mongodb.sh` | |
| 2 | roboshop-redis | `02-redis.sh` | |
| 3 | roboshop-mysql | `03-mysql.sh` | |
| 4 | roboshop-rabbitmq | `04-rabbitmq.sh` | |
| 5 | roboshop-catalogue | `05-catalogue.sh` | MongoDB |
| 6 | roboshop-user | `06-user.sh` | MongoDB, Redis, and the demo user loaded by catalogue |
| 7 | roboshop-cart | `07-cart.sh` | Redis, Catalogue |
| 8 | roboshop-shipping | `08-shipping.sh` | MySQL, Cart |
| 9 | roboshop-payment | `09-payment.sh` | Cart, User, RabbitMQ |
| 10 | roboshop-dispatch | `10-dispatch.sh` | RabbitMQ |
| 11 | roboshop-frontend | `11-frontend.sh` | All backend services |

Run the script from inside the `shell-roboshop-new` folder: it copies the service files from there.

Every script is safe to run again. It skips what is already done, for example the database password or loading the data a second time.

---

## Checks

After the setup, every script checks its own work and prints `PASS` or `FAIL`:

```text
10:42:01 Installing Node.js ...  SUCCESS
10:42:05 System user roboshop already exists ...  SKIPPING
...
---- Checks ----
   PASS  service catalogue is running
   PASS  port 8080 is open
   PASS  can connect to mongodb.daws92s.store:27017
   PASS  http://localhost:8080/health returned 200
   PASS  http://localhost:8080/products returned 200

All checks passed
```

| Check | What it means when it fails |
|-------|-----------------------------|
| `service ... is not running` | The application crashed, see `journalctl -u <service>` |
| `nothing is listening on port ...` | The application did not start, or listens on another port |
| `cannot connect to <server>:<port>` | That server is down, the Route53 record is wrong, or its security group does not allow this server |
| `... returned 503` | The application runs, but one of its databases is down |
| `... returned 000` | Nothing answered at all |

The checks only read, they change nothing. To check a server again later, run the same script again.

---

## Logs

Each script writes the full output of every command to `/var/log/roboshop/<script-name>.log`, for example `/var/log/roboshop/05-catalogue.log`. When a step shows `FAILURE`, look at the end of that file:

```shell
tail -50 /var/log/roboshop/05-catalogue.log
```

The application logs are in journald:

```shell
journalctl -u catalogue -f
```

---

## Good to Know

- **Nginx reads the IPs of the backend servers only when it starts.** If you delete and create a backend server again, it gets a new IP. Run `systemctl restart nginx` on the frontend after that.
- Shipping builds with Maven. The first build downloads all the libraries and takes a few minutes.
- All files use Linux line endings (`.gitattributes`). If you edit them on Windows and see `$'\r': command not found`, the line endings were changed.

---

## Files

| File | Used by |
|------|---------|
| `common.sh` | All scripts: root check, `VALIDATE`, logs, and the check functions |
| `mongo.repo` | `01-mongodb.sh`, `05-catalogue.sh` (MongoDB client) |
| `rabbitmq.repo` | `04-rabbitmq.sh` |
| `catalogue.service`, `user.service`, `cart.service`, `shipping.service`, `payment.service`, `dispatch.service` | The matching scripts |
| `roboshop.conf` | `11-frontend.sh`, goes to `/etc/nginx/default.d/` |
