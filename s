{
	"AWSTemplateFormatVersion": "2010-09-09",
	"Description": "Start an ubuntu server with working Shadowsocks",
	"Parameters" : {
		"Password" : {
			"Description" : "password for shadowshock connection",
			"Type" : "String",
			"NoEcho":"true"
		},
		"ConnectionPort" : {
			"Description" : "connection port for shadowshock",
			"Type" : "Number",
			"Default" : "8389"
		},
		"KeyName" : {
			"Description" : "The existing key you created for the instance. If it is left empty, a new key will be generated",
			"Type" : "String",
			"Default" : ""
		}
	 },
	 "Conditions" : {
		"NewKey" : {"Fn::Equals" : [{"Ref":"KeyName"},""]}
	},
	"Resources": {
		"SsRole": {
		  "Type": "AWS::IAM::Role",
		  "Properties": {
				"AssumeRolePolicyDocument": {
				  "Version": "2012-10-17",
				  "Statement": [
					{
					  "Effect": "Allow",
					  "Principal": {
						"Service": [
						  "lambda.amazonaws.com",
						  "ec2.amazonaws.com"
						]
					  },
					  "Action": [
						"sts:AssumeRole"
					  ]
					}
				  ]
				},
				"Path": "/",
				"Policies": [ {
				   "PolicyName": "AccessPolicy",
				   "PolicyDocument": {
						  "Version" : "2012-10-17",
						  "Statement": [
							{
							  "Effect": "Allow",
							  "Action": [
								"ec2:*",
								"lambda:*"
							  ],
							  "Resource": "*"
							}
						  ]
					}
				}]
            }
		},
		"GenerateKey": {
		  "Type": "AWS::Lambda::Function",
		  "Condition" : "NewKey",
		  "Properties": {
				"Code": {
				  "ZipFile": {
					"Fn::Join": [
					  "\n",
					  [
						"import boto3",
						"import cfnresponse",
						"def generate_key(event, context):",
						"\ttry:",
						"\t\tkeyname=''",
						"\t\tkeymaterial=''",
						"\t\tclient = boto3.client('ec2')",
						"\t\tif event['RequestType']=='Create':",
						"\t\t\tresponse = client.create_key_pair(KeyName='keyforss')",
						"\t\t\tkeymaterial = response['KeyMaterial']",
						"\t\t\tkeyname = response['KeyName']",
						"\t\tif event['RequestType']=='Delete':",
						"\t\t\tresponse = client.delete_key_pair(KeyName='keyforss')",
						"\t\tresponseData = {'keyname':keyname,'keymaterial':keymaterial}",
						"\t\tcfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)",
						"\texcept Exception as e:",
						"\t\tresponseData = {'status':e.message}",
						"\t\tcfnresponse.send(event, context, cfnresponse.FAILED, responseData)"
					  ]
					]
				  }
				},
				"Handler": "index.generate_key",
				"Runtime": "python3.9",
				"Timeout": "100",
				"Role": {
				  "Fn::GetAtt": ["SsRole","Arn"]
				}
			}
		},
		"GetKeyInfo": {
		  "Type": "AWS::CloudFormation::CustomResource",
		  "Condition" : "NewKey",
		  "Version" : "1.0",
		  "Properties": {
			"ServiceToken": {"Fn::GetAtt":["GenerateKey","Arn"]}
		  }
		},
		"GetImageId": {
			"Type": "AWS::Lambda::Function",
			"Properties": {
				"Code": {
				  "ZipFile": {
					"Fn::Join": [
					  "\n",
					  [
						"import boto3",
						"import cfnresponse",
						"def get_imageid(event, context):",
						"\ttry:",
						"\t\timageId=''",
						"\t\tif event['RequestType']=='Create':",
						"\t\t\tclient = boto3.client('ec2')",
						"\t\t\timages=client.describe_images(Owners=['099720109477'],Filters=[{'Name':'name','Values':['ubuntu\/images\/hvm-ssd\/ubuntu-xenial-16.04-amd64-server*']}])",
						"\t\t\timageId = images['Images'][-1]['ImageId']",
						"\t\tresponseData = {}",
						"\t\tresponseData['imageId'] = imageId",
						"\t\tcfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)",
						"\texcept Exception as e:",
						"\t\tresponseData = {'status':e.message}",
						"\t\tcfnresponse.send(event, context, cfnresponse.FAILED, responseData)"
					  ]
					]
				  }
				},
				"Handler": "index.get_imageid",
				"Runtime": "python3.9",
				"Timeout": "100",
				"Role": {"Fn::GetAtt": ["SsRole","Arn"]}
			}
		},
		"CustomGetImageId": {
		  "Type": "AWS::CloudFormation::CustomResource",
		  "Version" : "1.0",
		  "Properties": {
			"ServiceToken": {"Fn::GetAtt":["GetImageId","Arn"]}
		  }
		},
		"MyEC2Instance" : {
			 "Type" : "AWS::EC2::Instance",
			 "Properties" : {
					"ImageId" : {"Fn::GetAtt":["CustomGetImageId","imageId"]},
					"InstanceType" : "t2.micro",
					"KeyName" : {"Fn::If":["NewKey",{"Fn::GetAtt":["GetKeyInfo","keyname"]},{"Ref":"KeyName"}]},
					"NetworkInterfaces": [ {
						  "AssociatePublicIpAddress": "true",
						  "DeviceIndex": "0",
						  "GroupSet": [{ "Ref" : "ServerSecurityGroup" }],
						  "SubnetId": { "Ref" : "Subnet" }
					}],
					"Tags" : [ {
						 "Key" : "Name",
						 "Value" : "shadowsocks"
					}],
					"UserData" : {
						 "Fn::Base64" : {
								"Fn::Join" : [ "\n", [
									"#!/bin/bash",
									"sudo apt-get update",
									"sudo apt-get -y install python-pip",
									"sudo pip install shadowsocks",
									"echo '{' |sudo tee \/etc\/shadowsocks.json -a",
									"echo '\"server\":\"0.0.0.0\",' |sudo tee \/etc\/shadowsocks.json -a",
									{ "Fn::Sub": [ "echo '\"server_port\":${port},' |sudo tee \/etc\/shadowsocks.json -a", {"port": {"Ref":"ConnectionPort"}}]},
									"echo '\"local_address\": \"127.0.0.1\",' |sudo tee \/etc\/shadowsocks.json -a",
									"echo '\"local_port\":1080,' |sudo tee \/etc\/shadowsocks.json -a",
									{ "Fn::Sub": [ "echo '\"password\":\"${PSW}\",' |sudo tee \/etc\/shadowsocks.json -a", {"PSW": {"Ref":"Password"}}]},
									"echo '\"timeout\":300,' |sudo tee \/etc\/shadowsocks.json -a",
									"echo '\"method\":\"aes-256-cfb\",' |sudo tee \/etc\/shadowsocks.json -a",
									"echo '\"fast_open\": false' |sudo tee \/etc\/shadowsocks.json -a",
									"echo '}' |sudo tee \/etc\/shadowsocks.json -a",
									"sudo ssserver -c \/etc\/shadowsocks.json -d start",
									""
								]
							 ]
						 }
					}
			 }
		},
		"ServerSecurityGroup" : {
			 "Type" : "AWS::EC2::SecurityGroup",
			 "Properties" : {
				"GroupDescription" : "Allow connection port and ssh",
				"VpcId": {
					"Ref": "Vpc"
				},
				 "SecurityGroupIngress" : [
					 {
						 "IpProtocol" : "tcp",
						 "FromPort" : {"Ref":"ConnectionPort"},
						 "ToPort" : {"Ref":"ConnectionPort"},
						 "CidrIp" : "0.0.0.0/0"
					 },{
						 "IpProtocol" : "tcp",
						 "FromPort" : "22",
						 "ToPort" : "22",
						 "CidrIp" : "0.0.0.0/0"
					 }
				 ]
			 }
		},
		"Vpc": {
		  "Type": "AWS::EC2::VPC",
		  "Properties": {
			"EnableDnsSupport": "true",
			"EnableDnsHostnames": "true",
			"CidrBlock": "10.1.0.0/16"
		  }
		},
		"Subnet": {
		  "Type": "AWS::EC2::Subnet",
		  "Properties": {
			"VpcId": {
			  "Ref": "Vpc"
			},
			"CidrBlock": "10.1.0.0/24"
		  }
		},
		"InternetGateway": {
		  "Type": "AWS::EC2::InternetGateway"
		},
		"VPCGatewayAttachment": {
		  "Type": "AWS::EC2::VPCGatewayAttachment",
		  "Properties": {
			"VpcId": {
			  "Ref": "Vpc"
			},
			"InternetGatewayId": {
			  "Ref": "InternetGateway"
			}
			}
		},
		 "PublicRoute": {
		  "Type": "AWS::EC2::Route",
		  "DependsOn": "VPCGatewayAttachment",
		  "Properties": {
			"RouteTableId": {
			  "Ref": "PublicRouteTable"
			},
			"DestinationCidrBlock": "0.0.0.0/0",
			"GatewayId": {
			  "Ref": "InternetGateway"
			}
		  }
		},
		"PublicRouteTable": {
		  "Type": "AWS::EC2::RouteTable",
		  "Properties": {
			"VpcId": {
			  "Ref": "Vpc"
			}
		  }
		},
		"PublicSubnetRouteTableAssociation": {
		  "Type": "AWS::EC2::SubnetRouteTableAssociation",
		  "Properties": {
			"SubnetId": {
			  "Ref": "Subnet"
			},
			"RouteTableId": {
			  "Ref": "PublicRouteTable"
			}
		  }
		}
	},
	"Outputs" : {
		"PrivateKey" : {
			"Description" : "Unencrypted PEM encoded RSA private key",
			"Condition" : "NewKey",
			"Value" : {"Fn::GetAtt":["GetKeyInfo","keymaterial"]}
		},
		"ShadowsockIp" : {
			"Description" : "The ip of the Shadowsocks server",
			"Value" : {"Fn::GetAtt":["MyEC2Instance","PublicIp"]}
		},
		"RemotePort" : {
			"Description" : "The remote port of Shadowsocks server",
			"Value" : {"Ref":"ConnectionPort"}
		}
	}
}